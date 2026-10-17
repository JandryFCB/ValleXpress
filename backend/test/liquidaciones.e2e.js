// Prueba de extremo a extremo de las LIQUIDACIONES (cobro semanal de la comisión a cada negocio, opción A):
// semana en curso, semana cerrada pendiente, semana vencida (el negocio deja de recibir pedidos), pago registrado
// por el administrador y la configuración (días de gracia, cuenta para transferir).
// Uso:  npm run test:liquidaciones   (desde la carpeta backend, con Docker/Postgres en marcha)
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3098, bd: 'vallexpress_test_liquidaciones' });
const { check, seccion, api } = t;
const ZONA = 'America/Guayaquil';

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    // Lleva un pedido a una semana pasada: el miércoles de hace N semanas (sin disparar el historial)
    const aSemana = (id, semanasAtras) => q(`SET session_replication_role = replica;
      UPDATE tpedidos SET fpedido = date_trunc('week', now() AT TIME ZONE '${ZONA}') - interval '${7 * Number(semanasAtras) - 2} days' + interval '12 hours'
       WHERE cpedido = ${Number(id)};
      SET session_replication_role = origin;`);
    const lunes = async (semanasAtras) => (await q(`SELECT to_char(date_trunc('week', now() AT TIME ZONE '${ZONA}')::date - ${7 * semanasAtras}, 'YYYY-MM-DD') AS d`))[0].d;
    const { hashClave } = require('../src/shared/utils/clave');
    await q("UPDATE tusuarios SET clavehash=$1 WHERE cusuario='admin' AND fhasta='2999-12-31 00:00:00-05'", [await hashClave('admin-secreta-1')]);
    const A = (await api('POST', '/api/auth/login', { email: 'admin', password: 'admin-secreta-1' })).body.token;

    seccion('1. Preparación');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: -0.18, longitud: -78.48 }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10 }, L)).body.producto;
    const negocioId = pizza.negocioId;
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = carlos.token;
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, C)).body.direccion;
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    const P = pedro.token;
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    const pedir = () => api('POST', '/api/pedidos', { negocioId, direccionId: dir.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 2 }] }, C);
    const entregar = async () => {
      const p = (await pedir()).body.pedido;
      for (const e of ['confirmado', 'listo']) await api('PATCH', `/api/mi-negocio/pedidos/${p.id}/estado`, { estado: e }, L);
      for (const paso of ['aceptar', 'recogido', 'entregado']) await api('PATCH', `/api/repartidor/pedidos/${p.id}/${paso}`, null, P);
      return p;
    };
    check('negocio, cliente y repartidor listos', !!pizza?.id && !!dir?.id);

    seccion('2. Semana en curso');
    const p1 = await entregar();
    let r = await api('GET', '/api/mi-negocio/liquidaciones', null, L);
    check('el negocio ve la semana en curso: 1 pedido, $20 vendidos, $2 de comisión (10 %), recibe $18', r.status === 200 && r.body.semanas[0]?.estado === 'en_curso' && r.body.semanas[0].pedidos === 1 && r.body.semanas[0].ventas === 20 && r.body.semanas[0].comision === 2 && r.body.semanas[0].recibeNegocio === 18, JSON.stringify(r.body));
    check('todavía no debe nada (la semana no termina)', r.body.saldoPendiente === 0 && r.body.bloqueado === false);
    r = await api('GET', '/api/mi-negocio/liquidaciones', null, C);
    check('un cliente no ve liquidaciones: 403', r.status === 403);

    seccion('3. Semana cerrada: pendiente');
    await aSemana(p1.id, 1);
    r = await api('GET', '/api/mi-negocio/liquidaciones', null, L);
    const semanaPasada = await lunes(1);
    check('la semana pasada queda pendiente con su fecha de vencimiento', r.body.semanas[0]?.semana === semanaPasada && r.body.semanas[0].estado === 'pendiente' && !!r.body.semanas[0].vence, JSON.stringify(r.body.semanas));
    check('debe $2.00 pero aún puede recibir pedidos', r.body.saldoPendiente === 2 && r.body.bloqueado === false);
    r = await api('GET', '/api/admin/liquidaciones', null, A);
    const fila = r.body.pendientes?.find((x) => x.negocioId === negocioId);
    check('el admin ve al negocio con 1 semana y $2.00 por cobrar', fila?.semanas === 1 && fila.saldo === 2 && fila.bloqueado === false, JSON.stringify(r.body));
    r = await pedir();
    check('con una semana pendiente (sin vencer) sí se puede pedir', r.status === 201);
    const p2 = r.body.pedido;
    await api('PATCH', `/api/mi-negocio/pedidos/${p2.id}/estado`, { estado: 'rechazado', motivo: 'prueba' }, L);

    seccion('4. Semana vencida: deja de recibir pedidos');
    await aSemana(p1.id, 3);
    r = await api('GET', '/api/mi-negocio/liquidaciones', null, L);
    const semanaVieja = await lunes(3);
    check('la semana de hace 3 semanas quedó vencida y el negocio bloqueado', r.body.semanas[0]?.semana === semanaVieja && r.body.semanas[0].estado === 'vencida' && r.body.bloqueado === true, JSON.stringify(r.body));
    r = await api('GET', '/api/mi-negocio', null, L);
    check('el dueño ve que está bloqueado por deuda', r.body.negocio?.bloqueadoPorDeuda === true);
    r = await api('GET', '/api/negocios', null, C);
    check('para los clientes, el negocio no está recibiendo pedidos', r.body.negocios.find((n) => n.id === negocioId)?.aceptaPedidos === false);
    r = await pedir();
    check('pedir: 409 con un mensaje que no expone la deuda', r.status === 409 && r.body.code === 'NEGOCIOCONDEUDA' && !/deuda|comisi/i.test(r.body.error), JSON.stringify(r.body));
    r = await api('GET', '/api/admin/liquidaciones', null, A);
    check('el admin lo ve marcado como bloqueado', r.body.pendientes.find((x) => x.negocioId === negocioId)?.bloqueado === true);

    seccion('5. El admin registra el pago');
    r = await api('POST', `/api/admin/negocios/${negocioId}/liquidaciones`, { semana: await lunes(2) }, A);
    check('una semana sin ventas: 404', r.status === 404);
    r = await api('POST', `/api/admin/negocios/${negocioId}/liquidaciones`, { semana: 'ayer' }, A);
    check('semana mal escrita: 400', r.status === 400);
    r = await api('POST', `/api/admin/negocios/${negocioId}/liquidaciones`, { semana: semanaVieja }, L);
    check('un vendedor no registra pagos: 403', r.status === 403);
    r = await api('POST', `/api/admin/negocios/${negocioId}/liquidaciones`, { semana: semanaVieja, referencia: 'TRF-001234' }, A);
    check('pago registrado: la semana queda pagada y el negocio desbloqueado', r.status === 201 && r.body.semanas[0].estado === 'pagada' && r.body.semanas[0].referencia === 'TRF-001234' && r.body.bloqueado === false && r.body.saldoPendiente === 0, JSON.stringify(r.body));
    r = await api('POST', `/api/admin/negocios/${negocioId}/liquidaciones`, { semana: semanaVieja }, A);
    check('pagarla otra vez: 409', r.status === 409 && r.body.code === 'YAPAGADA');
    check('en la BD queda la foto de lo cobrado', Number((await q('SELECT comision FROM tliquidaciones WHERE cnegocio=$1', [negocioId]))[0]?.comision) === 2);
    check('el negocio recibe "Recibimos tu pago"', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='liquidacion_pagada'", [luis.usuario.id])).length === 1);
    check('y queda en la auditoría', (await q("SELECT 1 FROM tauditoria WHERE accion='LIQUIDACIONPAGADA'")).length === 1);
    r = await pedir();
    check('ya puede recibir pedidos otra vez', r.status === 201);
    const p3 = (await entregar());
    r = await api('POST', `/api/admin/negocios/${negocioId}/liquidaciones`, { semana: await lunes(0) }, A);
    check('la semana en curso no se puede liquidar todavía: 409', r.status === 409 && r.body.code === 'SEMANAENCURSO', JSON.stringify(r.body));
    check('(pedido de esta semana entregado)', !!p3?.id);

    seccion('6. Configuración del cobro');
    const cuenta = { banco: 'Banco Pichincha', tipo: 'ahorros', numero: '2200112233', titular: 'ValleXpress S.A.S.', identificacion: '1790012345001' };
    r = await api('PUT', '/api/admin/liquidaciones/config', { diasGracia: 3, cuenta }, A);
    check('el admin fija 3 días de gracia y la cuenta con sus datos', r.status === 200 && r.body.config.diasGracia === 3 && r.body.config.cuenta.banco === 'Banco Pichincha' && r.body.config.cuenta.completa === true, JSON.stringify(r.body));
    r = await api('GET', '/api/mi-negocio/liquidaciones', null, L);
    check('el negocio ve banco, tipo, número, titular y RUC', r.body.cuenta.numero === '2200112233' && r.body.cuenta.tipo === 'ahorros' && r.body.cuenta.titular === 'ValleXpress S.A.S.' && r.body.cuenta.identificacion === '1790012345001' && r.body.diasGracia === 3);
    r = await api('PUT', '/api/admin/liquidaciones/config', { cuenta: { titular: 'Jandry C.' } }, A);
    check('cambiar solo el titular conserva lo demás', r.body.config.cuenta.titular === 'Jandry C.' && r.body.config.cuenta.numero === '2200112233');
    r = await api('PUT', '/api/admin/liquidaciones/config', { diasGracia: 99 }, A);
    check('días de gracia fuera de rango: 400', r.status === 400);
    r = await api('PUT', '/api/admin/liquidaciones/config', { cuenta: { tipo: 'bitcoin' } }, A);
    check('tipo de cuenta inválido: 400', r.status === 400);
    r = await api('PUT', '/api/admin/liquidaciones/config', { cuenta: { numero: '22-ABC' } }, A);
    check('número de cuenta con letras: 400', r.status === 400);

    seccion('7. Comprobante de pago');
    await api('PUT', '/api/admin/liquidaciones/config', { diasGracia: 7 }, A);
    const p4 = await entregar();
    await aSemana(p4.id, 4);
    const semana4 = await lunes(4);
    r = await api('GET', '/api/mi-negocio/liquidaciones', null, L);
    check('semana de hace 4 semanas vencida: bloqueado', r.body.bloqueado === true && r.body.semanas.find((x) => x.semana === semana4)?.estado === 'vencida', JSON.stringify(r.body.semanas));
    const foto = await t.imagen(400, 600, 'jpeg');
    r = await api('POST', '/api/mi-negocio/liquidaciones/comprobante', { semana: semana4, referencia: 'TRF-77' }, L);
    check('sin la foto: 400', r.status === 400);
    r = await api('POST', '/api/mi-negocio/liquidaciones/comprobante', { semana: semana4, imagen: foto, referencia: 'TRF-77' }, L);
    const sem = r.body.semanas?.find((x) => x.semana === semana4);
    check('sube el comprobante: la semana queda en revisión con su foto', r.status === 201 && sem?.estado === 'en_revision' && sem.comprobante?.estado === 'enviado' && /^http/.test(sem.comprobante.imagen || ''), JSON.stringify(r.body));
    check('con el comprobante en revisión ya no está bloqueado', r.body.bloqueado === false);
    r = await pedir();
    check('y puede recibir pedidos', r.status === 201);
    await api('PATCH', `/api/mi-negocio/pedidos/${r.body.pedido.id}/estado`, { estado: 'rechazado', motivo: 'prueba' }, L);
    r = await api('POST', '/api/mi-negocio/liquidaciones/comprobante', { semana: semana4, imagen: foto }, L);
    check('otro comprobante de la misma semana mientras se revisa: 409', r.status === 409 && r.body.code === 'COMPROBANTEENREVISION');
    check('a los administradores les llega "Comprobante por revisar"', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario='admin' AND tipo='comprobante_nuevo'")).length === 1);
    r = await api('GET', '/api/admin/liquidaciones', null, A);
    check('el admin ve 1 comprobante por revisar del negocio', r.body.pendientes.find((x) => x.negocioId === negocioId)?.porRevisar === 1);
    r = await api('GET', `/api/admin/negocios/${negocioId}/liquidaciones`, null, A);
    const idComp = r.body.semanas.find((x) => x.semana === semana4)?.comprobante?.id;
    check('y lo abre con la foto', !!idComp);
    r = await api('POST', `/api/admin/comprobantes/${idComp}/rechazar`, { motivo: 'no' }, A);
    check('rechazar sin un motivo claro: 400', r.status === 400);
    r = await api('POST', `/api/admin/comprobantes/${idComp}/rechazar`, { motivo: 'La foto no se lee' }, A);
    check('rechazado: la semana vuelve a vencida y el negocio se bloquea otra vez', r.status === 200 && r.body.semanas.find((x) => x.semana === semana4)?.estado === 'vencida' && r.body.bloqueado === true, JSON.stringify(r.body.semanas));
    check('el negocio recibe el motivo', (await q("SELECT mensaje FROM tnotificaciones WHERE cusuario=$1 AND tipo='comprobante_rechazado'", [luis.usuario.id]))[0]?.mensaje.includes('La foto no se lee'));
    r = await api('GET', '/api/mi-negocio/liquidaciones', null, L);
    check('y lo ve en su semana', r.body.semanas.find((x) => x.semana === semana4)?.comprobante?.motivoRechazo === 'La foto no se lee');
    r = await api('POST', `/api/admin/comprobantes/${idComp}/aprobar`, null, A);
    check('un comprobante ya revisado no se vuelve a revisar: 409', r.status === 409 && r.body.code === 'COMPROBANTEREVISADO');
    r = await api('POST', '/api/mi-negocio/liquidaciones/comprobante', { semana: semana4, imagen: foto, referencia: 'TRF-78' }, L);
    const idComp2 = r.body.semanas?.find((x) => x.semana === semana4)?.comprobante?.id;
    check('sube uno nuevo', r.status === 201 && idComp2 && idComp2 !== idComp);
    r = await api('POST', `/api/admin/comprobantes/${idComp2}/aprobar`, null, L);
    check('un vendedor no aprueba comprobantes: 403', r.status === 403);
    r = await api('POST', `/api/admin/comprobantes/${idComp2}/aprobar`, null, A);
    const pagada = r.body.semanas?.find((x) => x.semana === semana4);
    check('aprobado: la semana queda pagada con la referencia del negocio y se desbloquea', r.status === 200 && pagada?.estado === 'pagada' && pagada.referencia === 'TRF-78' && r.body.bloqueado === false, JSON.stringify(r.body));
    check('el negocio recibe "Recibimos tu pago" (2 en total)', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='liquidacion_pagada'", [luis.usuario.id])).length === 2);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
