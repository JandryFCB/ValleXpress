// Prueba de extremo a extremo de los PEDIDOS: crear (con todas sus reglas), stock, estados del negocio, cancelar,
// rechazar, recibir, calificar, notificaciones y avisos en vivo por socket.
// Uso:  npm run test:pedidos   (desde la carpeta backend, con Docker/Postgres en marcha)
// Crea su PROPIA base temporal, levanta el servidor contra ella y al terminar borra todo.
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3096, bd: 'vallexpress_test_pedidos' });
const { check, seccion, api } = t;
const VIGENTE = "'2999-12-31 00:00:00-05'";
const LOCAL = { lat: -0.18, lng: -78.48 };

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    // Envío plano de $1.5 (sin valor por km): esta prueba no es de tarifas (eso lo cubre tarifas.e2e.js)
    await q("UPDATE tconfiguraciones SET valor = CASE cconfiguracion WHEN 'ENVIOBASE' THEN '1.5'::jsonb ELSE '0'::jsonb END WHERE cconfiguracion IN ('ENVIOBASE','ENVIOPORKM') AND fhasta = '2999-12-31 00:00:00-05'");

    seccion('1. Preparación: negocio, productos y clientes');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis', categoriaNegocio: '001' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio', { pedidoMinimo: 5, tiempoPreparacion: 20, radioKm: 5 }, L);
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas y Colón', latitud: LOCAL.lat, longitud: LOCAL.lng }, L);
    const crearProd = async (datos) => (await api('POST', '/api/mi-negocio/productos', datos, L)).body.producto;
    const pizza = await crearProd({ nombre: 'Pizza margarita', precio: 8.5, seccion: 'Pizzas' });
    const cola = await crearProd({ nombre: 'Cola', precio: 1.25, seccion: 'Bebidas', controlaStock: true, stock: 3 });
    const oculto = await crearProd({ nombre: 'Secreto', precio: 3, estado: 'oculto' });
    check('negocio con local y 3 productos (uno con stock 3)', !!pizza?.id && !!cola?.id && !!oculto?.id && cola.stock === 3);

    const ana = await t.registrar('ana@test.com', 'Ana', 'Paz', 'vendedor', { nombreNegocio: 'Panadería Ana' });
    const panAna = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pan', precio: 6 }, ana.token)).body.producto;

    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = carlos.token;
    const dirCerca = (await api('POST', '/api/direcciones', { nombre: 'Casa', direccion: 'Calle 1', referencia: 'Portón verde', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, C)).body.direccion;
    const dirLejos = (await api('POST', '/api/direcciones', { nombre: 'Finca', direccion: 'Lejos', latitud: -0.5, longitud: -78.6, tipo: 'OTR' }, C)).body.direccion;
    const maria = await t.registrar('maria@test.com', 'María', 'León', 'cliente');
    const M = maria.token;
    const dirMaria = (await api('POST', '/api/direcciones', { nombre: 'Casa', direccion: 'Calle 2', latitud: -0.181, longitud: -78.481, tipo: 'DOM' }, M)).body.direccion;
    check('clientes con direcciones (una cerca y una a más de 5 km)', !!dirCerca?.id && !!dirLejos?.id && !!dirMaria?.id, JSON.stringify(dirCerca));

    const pedidoBase = { negocioId: pizza.negocioId, direccionId: dirCerca.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 1 }] };

    seccion('2. Métodos de pago');
    let r = await api('GET', '/api/pedidos/metodos-pago', null, C);
    check('solo efectivo y transferencia están activos', r.status === 200 && r.body.metodos.map((m) => m.codigo).join() === 'efectivo,transferencia', JSON.stringify(r.body));

    seccion('3. Reglas al crear un pedido');
    r = await api('POST', '/api/pedidos', pedidoBase, C);
    check('negocio cerrado: 409 NEGOCIOCERRADO', r.status === 409 && r.body.code === 'NEGOCIOCERRADO', JSON.stringify(r.body));
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true, aceptaPedidos: false }, L);
    r = await api('POST', '/api/pedidos', pedidoBase, C);
    check('abierto pero sin aceptar pedidos: 409 NEGOCIONOACEPTA', r.status === 409 && r.body.code === 'NEGOCIONOACEPTA');
    await api('PATCH', '/api/mi-negocio/estado', { aceptaPedidos: true }, L);
    r = await api('POST', '/api/pedidos', { ...pedidoBase, metodoPago: 'tarjeta' }, C);
    check('método de pago inactivo (tarjeta): 400', r.status === 400 && r.body.code === 'METODOPAGOINVALIDO');
    r = await api('POST', '/api/pedidos', { ...pedidoBase, direccionId: dirMaria.id }, C);
    check('dirección de otra persona: 404', r.status === 404 && r.body.code === 'DIRECCIONNOENCONTRADA');
    r = await api('POST', '/api/pedidos', { ...pedidoBase, direccionId: dirLejos.id }, C);
    check('dirección fuera del radio de entrega: 409 FUERADECOBERTURA con la distancia', r.status === 409 && r.body.code === 'FUERADECOBERTURA' && r.body.distanciaKm > 5, JSON.stringify(r.body));
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [{ productoId: panAna.id, cantidad: 1 }] }, C);
    check('producto de otro negocio: 404', r.status === 404 && r.body.code === 'PRODUCTONOENCONTRADO');
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [{ productoId: oculto.id, cantidad: 2 }] }, C);
    check('producto oculto: 409 PRODUCTONODISPONIBLE', r.status === 409 && r.body.code === 'PRODUCTONODISPONIBLE');
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [{ productoId: cola.id, cantidad: 2 }] }, C);
    check('no llega al pedido mínimo ($2.50 < $5): 400 PEDIDOMINIMO', r.status === 400 && r.body.code === 'PEDIDOMINIMO' && r.body.pedidoMinimo === 5);
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [{ productoId: pizza.id, cantidad: 1 }, { productoId: cola.id, cantidad: 4 }] }, C);
    check('más unidades que el stock: 409 STOCKINSUFICIENTE con lo disponible', r.status === 409 && r.body.code === 'STOCKINSUFICIENTE' && r.body.disponible === 3, JSON.stringify(r.body));
    check('...y el stock no se tocó (la transacción se deshizo)', (await q('SELECT stock FROM tproductosinventario WHERE cproducto=$1', [cola.id]))[0].stock === 3);
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [] }, C);
    check('sin productos: 400', r.status === 400);
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [{ productoId: pizza.id, cantidad: 0 }] }, C);
    check('cantidad 0: 400', r.status === 400);
    r = await api('POST', '/api/pedidos', pedidoBase, L);
    check('un vendedor no puede hacer pedidos: 403', r.status === 403);
    r = await api('POST', '/api/pedidos', pedidoBase);
    check('sin sesión: 401', r.status === 401);

    seccion('4. Crear un pedido');
    const sLuis = await t.conectar(L);
    const sCarlos = await t.conectar(C);
    check('vendedor y cliente conectados por socket', !sLuis.error && !sCarlos.error, sLuis.error || sCarlos.error);
    const avisoNuevo = t.esperar(sLuis, 'notificacion');
    const vivoNuevo = t.esperar(sLuis, 'pedido:actualizado');
    r = await api('POST', '/api/pedidos', {
      ...pedidoBase,
      notas: 'Tocar el timbre',
      productos: [{ productoId: pizza.id, cantidad: 1, notas: 'Sin aceitunas', precio: 0.01 }, { productoId: cola.id, cantidad: 2 }, { productoId: pizza.id, cantidad: 1 }],
    }, C);
    const p1 = r.body.pedido;
    check('201 con el pedido', r.status === 201 && p1?.id === 1 && p1.estado === 'pendiente', JSON.stringify(r.body));
    check('el mismo producto repetido se suma en una línea (2 líneas: pizza x2, cola x2)', p1.productos.length === 2 && p1.productos[0].cantidad === 2 && p1.productos[0].notas === 'Sin aceitunas' && p1.cantidadProductos === 4);
    check('montos de la BD (el precio enviado se ignora): 17 + 2.50 + envío 1.50 = 21', p1.subtotal === 19.5 && p1.costoEnvio === 1.5 && p1.total === 21 && p1.productos[0].precioUnitario === 8.5, JSON.stringify(p1));
    check('tiempo estimado = preparación (20) + entrega (15)', p1.tiempoEstimado === 35);
    check('dirección copiada en el pedido y datos del negocio', p1.entrega.direccion === 'Calle 1' && p1.entrega.referencia === 'Portón verde' && p1.negocio.nombre === 'Pizzería Luis' && p1.negocio.local.latitud === LOCAL.lat);
    check('línea de tiempo: pendiente', p1.lineaTiempo.length === 1 && p1.lineaTiempo[0].estado === 'pendiente');
    check('el cliente no recibe sus propios datos de contacto', p1.cliente === undefined);
    check('stock descontado: la cola queda en 1', (await q('SELECT stock FROM tproductosinventario WHERE cproducto=$1', [cola.id]))[0].stock === 1);
    const aviso = await avisoNuevo;
    check('el negocio recibe la notificación por socket', aviso?.tipo === 'pedido_nuevo' && aviso.pedidoId === 1, JSON.stringify(aviso));
    check('...y el evento en vivo para refrescar su pantalla', (await vivoNuevo)?.estado === 'pendiente');
    check('la notificación queda guardada para el dueño', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='pedido_nuevo' AND cpedido=1", [luis.usuario.id])).length === 1);

    await api('PUT', `/api/mi-negocio/productos/${pizza.id}`, { precio: 10 }, L);
    r = await api('GET', '/api/pedidos/1', null, C);
    check('si el negocio cambia el precio después, el pedido conserva el de ese momento', r.body.pedido.productos[0].precioUnitario === 8.5 && r.body.pedido.total === 21);

    seccion('5. Quién puede ver el pedido');
    check('el cliente lo ve', r.status === 200);
    r = await api('GET', '/api/pedidos/1', null, M);
    check('otro cliente: 404', r.status === 404 && r.body.code === 'PEDIDONOENCONTRADO');
    r = await api('GET', '/api/pedidos/1', null, ana.token);
    check('otro vendedor: 404', r.status === 404);
    r = await api('GET', '/api/pedidos/1', null, L);
    check('el dueño del negocio lo ve, con los datos del cliente', r.status === 200 && r.body.pedido.cliente?.nombre === 'Carlos' && !!r.body.pedido.cliente.telefono);
    r = await api('GET', '/api/pedidos/abc', null, C);
    check('ID inválido: 400', r.status === 400);
    r = await api('GET', '/api/pedidos/mis-pedidos?estado=activos', null, C);
    check('mis pedidos activos: 1', r.status === 200 && r.body.pedidos.length === 1 && r.body.pagination.total === 1);
    r = await api('GET', '/api/pedidos/mis-pedidos?estado=historial', null, C);
    check('historial: 0', r.status === 200 && r.body.pedidos.length === 0);
    r = await api('GET', '/api/mi-negocio/pedidos?estado=activos', null, L);
    check('el negocio ve su pedido activo con el cliente', r.status === 200 && r.body.pedidos.length === 1 && r.body.pedidos[0].cliente.nombre === 'Carlos');
    r = await api('GET', '/api/mi-negocio/pedidos', null, ana.token);
    check('otro negocio no ve nada', r.status === 200 && r.body.pedidos.length === 0);
    r = await api('GET', '/api/mi-negocio/resumen', null, L);
    check('resumen del día: 1 pedido hoy y lo vendido en productos', r.status === 200 && r.body.pedidosHoy === 1 && r.body.vendidoHoy > 0 && r.body.vendidoSemanaPasada === 0, JSON.stringify(r.body));
    r = await api('GET', '/api/mi-negocio/resumen', null, C);
    check('un cliente no ve el resumen de un negocio: 403', r.status === 403);

    seccion('6. Cancelar (cliente)');
    r = await api('POST', '/api/pedidos', { ...pedidoBase, direccionId: dirMaria.id, productos: [{ productoId: pizza.id, cantidad: 1 }, { productoId: cola.id, cantidad: 1 }] }, M);
    const p2 = r.body.pedido;
    check('María pide la última cola', r.status === 201 && p2.id === 2 && p2.total === 12.75, JSON.stringify(r.body));
    let cola2 = (await api('GET', `/api/negocios/${pizza.negocioId}/productos`, null, C)).body.productos.find((p) => p.id === cola.id);
    check('stock 0: la cola pasa sola a "agotado"', cola2.estado === 'agotado' && cola2.disponible === false);
    r = await api('PATCH', '/api/pedidos/2/cancelar', { motivo: 'Me equivoqué' }, C);
    check('Carlos no puede cancelar el pedido de María: 404', r.status === 404);
    r = await api('PATCH', '/api/pedidos/2/cancelar', { motivo: 'Me equivoqué' }, M);
    check('María lo cancela: 200 cancelado con motivo', r.status === 200 && r.body.pedido.estado === 'cancelado' && r.body.pedido.motivoCancelacion === 'Me equivoqué');
    cola2 = (await api('GET', `/api/negocios/${pizza.negocioId}/productos`, null, C)).body.productos.find((p) => p.id === cola.id);
    check('el stock vuelve (1) y la cola vuelve a "disponible"', cola2.estado === 'disponible' && (await q('SELECT stock FROM tproductosinventario WHERE cproducto=$1', [cola.id]))[0].stock === 1);
    r = await api('PATCH', '/api/pedidos/2/cancelar', {}, M);
    check('cancelarlo otra vez: 409', r.status === 409);
    check('el negocio recibe el aviso de cancelación', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='pedido_cancelado'", [luis.usuario.id])).length === 1);

    seccion('7. Estados del negocio');
    r = await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'listo' }, L);
    check('de pendiente a listo directo: 409 TRANSICIONINVALIDA', r.status === 409 && r.body.code === 'TRANSICIONINVALIDA');
    r = await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'en_camino' }, L);
    check('el negocio no puede poner "en camino": 400', r.status === 400);
    r = await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'confirmado' }, ana.token);
    check('otro negocio: 404', r.status === 404);
    r = await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'confirmado' }, C);
    check('un cliente: 403', r.status === 403);
    const avisoConfirmado = t.esperar(sCarlos, 'notificacion');
    r = await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'confirmado', tiempoEstimado: 40 }, L);
    check('confirmar con tiempo estimado: 200', r.status === 200 && r.body.pedido.estado === 'confirmado' && r.body.pedido.tiempoEstimado === 40, JSON.stringify(r.body));
    const a2 = await avisoConfirmado;
    check('el cliente recibe "pedido confirmado" en vivo con el tiempo', a2?.tipo === 'pedido_confirmado' && /40 min/.test(a2.mensaje), JSON.stringify(a2));
    r = await api('PATCH', '/api/pedidos/1/cancelar', {}, C);
    check('ya confirmado, el cliente no puede cancelar: 409 PEDIDOENPROCESO', r.status === 409 && r.body.code === 'PEDIDOENPROCESO');
    await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'preparando' }, L);
    r = await api('PATCH', '/api/mi-negocio/pedidos/1/estado', { estado: 'listo' }, L);
    check('preparando y luego listo: 200', r.status === 200 && r.body.pedido.estado === 'listo');
    const lt = r.body.pedido.lineaTiempo;
    check('línea de tiempo en orden: pendiente, confirmado, preparando, listo', lt.map((x) => x.estado).join() === 'pendiente,confirmado,preparando,listo' && lt.every((x, i) => i === 0 || new Date(x.fecha) >= new Date(lt[i - 1].fecha)), JSON.stringify(lt));
    const h = await q('SELECT cestatuspedido e, cusuario_modificacion m FROM tpedidos WHERE cpedido=1 ORDER BY fdesde');
    check('cada cambio queda en el historial de TPEDIDOS con quién lo hizo', h.length === 4 && h.at(-1).m === luis.usuario.id && (await q(`SELECT 1 FROM tpedidos WHERE cpedido=1 AND fhasta=${VIGENTE}`)).length === 1, JSON.stringify(h));

    seccion('8. Rechazar (negocio)');
    r = await api('POST', '/api/pedidos', { ...pedidoBase, productos: [{ productoId: pizza.id, cantidad: 1 }, { productoId: cola.id, cantidad: 1 }] }, C);
    const p3 = r.body.pedido;
    check('otro pedido de Carlos (precio nuevo de la pizza: 10)', r.status === 201 && p3.subtotal === 11.25, JSON.stringify(r.body));
    r = await api('PATCH', `/api/mi-negocio/pedidos/${p3.id}/estado`, { estado: 'rechazado', motivo: 'Se acabó la masa' }, L);
    check('rechazado con motivo', r.status === 200 && r.body.pedido.estado === 'rechazado' && r.body.pedido.motivoCancelacion === 'Se acabó la masa');
    check('el stock de la cola se devuelve', (await q('SELECT stock FROM tproductosinventario WHERE cproducto=$1', [cola.id]))[0].stock === 1);
    check('el cliente recibe el aviso con el motivo', (await q("SELECT mensaje FROM tnotificaciones WHERE cusuario=$1 AND tipo='pedido_rechazado'", [carlos.usuario.id]))[0]?.mensaje.includes('Se acabó la masa'));

    seccion('9. Recibir y calificar (cliente)');
    r = await api('POST', '/api/pedidos/1/calificar', { puntuacion: 5 }, C);
    check('calificar antes de recibirlo: 409', r.status === 409 && r.body.code === 'PEDIDONOENTREGADO');
    r = await api('PATCH', '/api/pedidos/1/recibido', null, C);
    check('marcar recibido estando "listo": 409', r.status === 409 && r.body.code === 'TRANSICIONINVALIDA');
    // El repartidor (flujo 4) es quien lo entrega; aquí se simula directo en la BD
    await q("UPDATE tpedidos SET cestatuspedido='007' WHERE cpedido=1 AND fhasta='2999-12-31 00:00:00-05'");
    r = await api('PATCH', '/api/pedidos/1/recibido', null, M);
    check('otro cliente no puede marcarlo: 404', r.status === 404);
    r = await api('PATCH', '/api/pedidos/1/recibido', null, C);
    check('entregado -> recibido: 200, queda pagado', r.status === 200 && r.body.pedido.estado === 'recibido' && r.body.pedido.pagado === true);
    const est = (await q('SELECT numeropedidos FROM tnegociosestado WHERE cnegocio=$1', [pizza.negocioId]))[0];
    const vend = await q('SELECT cproducto, numerovendidos FROM tproductosinventario WHERE cproducto = ANY($1) ORDER BY cproducto', [[pizza.id, cola.id]]);
    check('contadores: 1 pedido del negocio, 2 pizzas y 2 colas vendidas', est.numeropedidos === 1 && vend[0].numerovendidos === 2 && vend[1].numerovendidos === 2, JSON.stringify(vend));
    r = await api('POST', '/api/pedidos/1/calificar', { puntuacion: 6 }, C);
    check('6 estrellas: 400', r.status === 400);
    r = await api('POST', '/api/pedidos/1/calificar', { puntuacion: 4, comentario: 'Muy rica' }, C);
    check('calificar al negocio: 200 con la calificación en el pedido', r.status === 200 && r.body.pedido.calificacion?.puntuacion === 4 && r.body.pedido.calificacion.comentario === 'Muy rica');
    r = await api('POST', '/api/pedidos/1/calificar', { puntuacion: 5 }, C);
    check('calificar otra vez: 409 YACALIFICADO', r.status === 409 && r.body.code === 'YACALIFICADO');
    r = await api('POST', '/api/pedidos/1/calificar', { puntuacion: 5, destino: 'repartidor' }, C);
    check('al repartidor (no tuvo): 400 SINREPARTIDOR', r.status === 400 && r.body.code === 'SINREPARTIDOR');
    r = await api('GET', `/api/negocios/${pizza.negocioId}`, null, M);
    check('el negocio queda con 4.0 de 1 calificación', r.body.negocio.calificacion === 4 && r.body.negocio.numeroCalificaciones === 1 && r.body.negocio.numeroPedidos === 1, JSON.stringify(r.body.negocio));
    r = await api('GET', '/api/pedidos/mis-pedidos?estado=historial', null, C);
    check('historial de Carlos: recibido y rechazado, el más nuevo primero', r.body.pedidos.length === 2 && r.body.pedidos[0].estado === 'rechazado' && r.body.pedidos[1].estado === 'recibido');

    seccion('10. Notificaciones');
    r = await api('GET', '/api/notificaciones', null, C);
    const notifs = r.body.notificaciones;
    check('Carlos tiene sus avisos (confirmado, preparando, listo, rechazado), el más nuevo primero', r.status === 200 && notifs.length === 4 && notifs[0].tipo === 'pedido_rechazado' && r.body.noLeidas === 4, JSON.stringify(notifs.map((n) => n.tipo)));
    r = await api('GET', '/api/notificaciones/no-leidas', null, C);
    check('contador de no leídas: 4', r.body.noLeidas === 4);
    r = await api('PATCH', `/api/notificaciones/${notifs[0].id}/leida`, null, M);
    check('marcar la de otro: 404', r.status === 404);
    r = await api('PATCH', `/api/notificaciones/${notifs[0].id}/leida`, null, C);
    check('marcar una como leída: 200', r.status === 200 && (await api('GET', '/api/notificaciones/no-leidas', null, C)).body.noLeidas === 3);
    r = await api('PATCH', '/api/notificaciones/leer-todas', null, C);
    check('leer todas: marca las 3 restantes', r.status === 200 && r.body.marcadas === 3 && (await api('GET', '/api/notificaciones/no-leidas', null, C)).body.noLeidas === 0);
    r = await api('POST', '/api/notificaciones/dispositivo', { token: 'token-fcm-de-prueba', plataforma: 'android', modelo: 'Redmi', appVer: '1.0.0' }, C);
    check('registrar el celular: 200 y queda en TDISPOSITIVOS', r.status === 200 && (await q("SELECT cusuario FROM tdispositivos WHERE tokenfcm='token-fcm-de-prueba'"))[0]?.cusuario === carlos.usuario.id);
    await api('POST', '/api/notificaciones/dispositivo', { token: 'token-fcm-de-prueba' }, M);
    check('el mismo celular con otra cuenta: el token pasa a esa cuenta (una sola fila)', (await q("SELECT cusuario FROM tdispositivos WHERE tokenfcm='token-fcm-de-prueba'")).map((x) => x.cusuario).join() === maria.usuario.id);
    r = await api('DELETE', '/api/notificaciones/dispositivo', { token: 'token-fcm-de-prueba' }, M);
    check('quitar el celular al cerrar sesión', r.status === 200 && (await q("SELECT 1 FROM tdispositivos WHERE tokenfcm='token-fcm-de-prueba'")).length === 0);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
