// Prueba de extremo a extremo del VIGILANTE DE VENCIMIENTOS: ningún pedido queda varado.
//   * listo sin que nadie lo recoja: aviso a los 30 min (negocio, admin y repartidores) y se cancela a los 60
//   * aceptado por un repartidor que no lo recoge: también vence (contado desde que quedó listo)
//   * pendiente sin respuesta del negocio: se cancela a los 30 min
//   * recogido o recién listo: no se toca
// Uso:  npm run test:vencimientos   (desde la carpeta backend, con Docker/Postgres en marcha)
// El vigilante corre cada 300 ms en la prueba y los pedidos se "envejecen" moviendo sus fechas en la BD.
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3096, bd: 'vallexpress_test_vencimientos', env: { VENCIMIENTO_CADA_MS: '300' } });
const { check, seccion, api } = t;
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    // Mueve hacia atrás todas las fechas de un pedido (sin disparar el historial: es solo para la prueba)
    const envejecer = (id, minutos) => q(`SET session_replication_role = replica;
      UPDATE tpedidos SET fdesde = fdesde - interval '${Number(minutos)} minutes', fpedido = fpedido - interval '${Number(minutos)} minutes' WHERE cpedido = ${Number(id)};
      SET session_replication_role = origin;`);
    const estado = async (id) => (await q("SELECT cestatuspedido AS e, motivocancelacion AS m FROM tpedidos WHERE cpedido=$1 AND fhasta='2999-12-31 00:00:00-05'", [id]))[0];
    const avisos = async (usuario, tipo, pedido) => (await q('SELECT mensaje FROM tnotificaciones WHERE cusuario=$1 AND tipo=$2 AND cpedido=$3', [usuario, tipo, pedido])).map((f) => f.mensaje);
    const esperarVigilante = () => dormir(1200);

    seccion('1. Preparación');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: -0.18, longitud: -78.48 }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10, controlaStock: true, stock: 10 }, L)).body.producto;
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = carlos.token;
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, C)).body.direccion;
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    const P = pedro.token;
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    const pedir = async () => (await api('POST', '/api/pedidos', { negocioId: pizza.negocioId, direccionId: dir.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 2 }] }, C)).body.pedido;
    const listo = async (id) => { await api('PATCH', `/api/mi-negocio/pedidos/${id}/estado`, { estado: 'confirmado' }, L); await api('PATCH', `/api/mi-negocio/pedidos/${id}/estado`, { estado: 'listo' }, L); };
    const stock = async () => (await q('SELECT stock FROM tproductosinventario WHERE cproducto=$1', [pizza.id]))[0]?.stock;
    check('negocio, cliente y repartidor en línea listos', !!pizza?.id && !!dir?.id && !!P);

    seccion('2. Listo y nadie lo recoge');
    const p1 = await pedir();
    await listo(p1.id);
    check('stock apartado: 10 - 2 = 8', (await stock()) === 8);
    await esperarVigilante();
    check('recién listo: el vigilante no lo toca', (await estado(p1.id)).e === '004');
    await envejecer(p1.id, 31);
    await esperarVigilante();
    check('a los 31 min sigue listo', (await estado(p1.id)).e === '004');
    const aviso = await avisos(luis.usuario.id, 'pedido_sin_repartidor', p1.id);
    check('el negocio recibe "nadie lo ha recogido" con los minutos que faltan', aviso.length === 1 && /29 min/.test(aviso[0]), JSON.stringify(aviso));
    check('el administrador también', (await avisos('admin', 'pedido_sin_repartidor', p1.id)).length === 1);
    check('y se vuelve a avisar a los repartidores en línea', (await avisos(pedro.usuario.id, 'pedido_disponible', p1.id)).length === 2);
    await esperarVigilante();
    check('el aviso no se repite en cada pasada', (await avisos(luis.usuario.id, 'pedido_sin_repartidor', p1.id)).length === 1);
    await envejecer(p1.id, 30);
    await esperarVigilante();
    const e1 = await estado(p1.id);
    check('a los 61 min se cancela solo, con el motivo', e1.e === '010' && e1.m === 'Cancelado automáticamente: ningún repartidor lo recogió a tiempo', JSON.stringify(e1));
    check('el stock vuelve (8 + 2 = 10)', (await stock()) === 10);
    check('el cliente recibe el aviso de la cancelación', (await avisos(carlos.usuario.id, 'pedido_cancelado', p1.id)).length === 1);
    check('el negocio también', (await avisos(luis.usuario.id, 'pedido_cancelado', p1.id)).length === 1);
    check('queda en la auditoría como "sistema"', (await q("SELECT 1 FROM tauditoria WHERE cusuario='sistema' AND accion='PEDIDOVENCIDO' AND entidadid=$1", [String(p1.id)])).length === 1);
    let r = await api('GET', '/api/repartidor/pedidos/libres', null, P);
    check('ya no aparece en los pedidos libres', !(r.body.listos || []).some((p) => p.id === p1.id));
    r = await api('GET', `/api/pedidos/${p1.id}`, null, C);
    check('el cliente lo ve cancelado con el motivo', r.body.pedido?.estado === 'cancelado' && /ningún repartidor/.test(r.body.pedido.motivoCancelacion || ''));

    seccion('3. Aceptado pero nunca recogido');
    const p2 = await pedir();
    await listo(p2.id);
    r = await api('PATCH', `/api/repartidor/pedidos/${p2.id}/aceptar`, null, P);
    check('el repartidor lo acepta (en camino)', r.status === 200 && (await estado(p2.id)).e === '005');
    await envejecer(p2.id, 61);
    await esperarVigilante();
    check('a los 61 min de listo sin recoger: cancelado', (await estado(p2.id)).e === '010');
    check('el repartidor recibe el aviso y queda libre', (await avisos(pedro.usuario.id, 'pedido_cancelado', p2.id)).length === 1);
    r = await api('PATCH', `/api/repartidor/pedidos/${p2.id}/recogido`, null, P);
    check('ya no puede marcarlo recogido: 409', r.status === 409);

    seccion('4. Recogido: no vence');
    const p3 = await pedir();
    await listo(p3.id);
    await api('PATCH', `/api/repartidor/pedidos/${p3.id}/aceptar`, null, P);
    await api('PATCH', `/api/repartidor/pedidos/${p3.id}/recogido`, null, P);
    await envejecer(p3.id, 120);
    await esperarVigilante();
    check('recogido hace 2 h: sigue su curso (lo resuelve el admin si hace falta)', (await estado(p3.id)).e === '006');
    await api('PATCH', `/api/repartidor/pedidos/${p3.id}/entregado`, null, P);

    seccion('5. El negocio no responde');
    const p4 = await pedir();
    await envejecer(p4.id, 29);
    await esperarVigilante();
    check('pendiente 29 min: sigue esperando', (await estado(p4.id)).e === '001');
    await envejecer(p4.id, 2);
    await esperarVigilante();
    const e4 = await estado(p4.id);
    check('pendiente 31 min: cancelado porque el negocio no respondió', e4.e === '010' && /Pizzería Luis no respondió a tiempo/.test(e4.m || ''), JSON.stringify(e4));
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p4.id}/estado`, { estado: 'confirmado' }, L);
    check('el negocio ya no puede confirmarlo: 409', r.status === 409);

  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
