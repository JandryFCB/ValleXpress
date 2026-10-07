// Prueba de extremo a extremo de PEDIDOS, DIRECCIONES, NOTIFICACIONES y SOCKETS.  Uso:  npm run test:pedidos
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3097, bd: 'vallexpress_pedidos' });
const { check, seccion, api, dormir, conectar, emitir, esperar } = t;

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const ana = await t.registrar('ana@test.com', 'Ana', 'Pérez', 'vendedor', { nombreNegocio: 'Café Ana' });
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const maria = await t.registrar('maria@test.com', 'Maria', 'Paz', 'cliente');
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Ruiz', 'repartidor', { vehiculo: 'Moto', placa: 'AB1234' });
    const rosa = await t.registrar('rosa@test.com', 'Rosa', 'Vega', 'repartidor', { vehiculo: 'Moto', placa: 'CD5678' });
    const T = { luis: luis.token, ana: ana.token, carlos: carlos.token, maria: maria.token, pedro: pedro.token, rosa: rosa.token };
    const venLuis = (await q("SELECT vendedor v FROM vendedores WHERE usuario='lmora'"))[0].v;
    const venAna = (await q("SELECT vendedor v FROM vendedores WHERE usuario='aperez'"))[0].v;
    const repPedro = (await q("SELECT repartidor r FROM repartidores WHERE usuario='pruiz'"))[0].r;
    const repRosa = (await q("SELECT repartidor r FROM repartidores WHERE usuario='rvega'"))[0].r;
    const prod = async (token, cuerpo) => (await api('POST', '/api/productos', cuerpo, token)).body.producto.id;
    const pizza = await prod(T.luis, { nombre: 'Pizza Margarita', precio: 5.5, stock: 10 });
    const agua = await prod(T.luis, { nombre: 'Agua mineral', precio: 1 });                  // sin control de stock
    const flan = await prod(T.luis, { nombre: 'Flan casero', precio: 3.25, stock: 2 });
    const jugo = await prod(T.luis, { nombre: 'Jugo de naranja', precio: 2, stock: 5 });
    const cafe = await prod(T.ana, { nombre: 'Café americano', precio: 1.25, stock: 50 });
    const stock = async (id) => (await q('SELECT stock, estado FROM productos WHERE producto=$1', [id]))[0];
    const estadoDe = async (id) => (await q('SELECT estado FROM pedidos WHERE pedido=$1', [id]))[0].estado;
    let r;

    seccion('1. Direcciones del cliente');
    r = await api('POST', '/api/direcciones', { nombre: 'Casa', direccion: 'Av. Amazonas N1-23', latitud: -0.18, longitud: -78.47, esPredeterminada: true, referencia: 'Portón negro' }, T.carlos);
    const dirCarlos = r.body.direccion?.id;
    check('crear dirección: 201, id DIR-000001, coordenadas numéricas y predeterminada', r.status === 201 && /^DIR-\d{6}$/.test(dirCarlos) && r.body.direccion.latitud === -0.18 && r.body.direccion.esPredeterminada === true && r.body.direccion.nombre === 'Casa');
    r = await api('POST', '/api/direcciones', { nombre: 'Oficina', direccion: 'Calle Sucre 45', latitud: -0.2, longitud: -78.5, esPredeterminada: true }, T.carlos);
    const dirCarlos2 = r.body.direccion.id;
    check('una nueva predeterminada desmarca la anterior (solo UNA por usuario)', (await q("SELECT count(*)::int n FROM direcciones WHERE usuario='cruiz' AND espredeterminada")).at(0).n === 1);
    r = await api('GET', '/api/direcciones/predeterminada', null, T.carlos);
    check('GET /predeterminada devuelve la Oficina', r.status === 200 && r.body.direccion.id === dirCarlos2);
    r = await api('PATCH', `/api/direcciones/${dirCarlos}/predeterminada`, null, T.carlos);
    check('PATCH /:id/predeterminada intercambia la predeterminada', r.status === 200 && r.body.direccion.esPredeterminada === true && (await api('GET', '/api/direcciones/predeterminada', null, T.carlos)).body.direccion.id === dirCarlos);
    r = await api('GET', '/api/direcciones', null, T.carlos);
    check('la lista trae la predeterminada primero', r.body.direcciones.length === 2 && r.body.direcciones[0].id === dirCarlos);
    check('sin predeterminada: 404 con { direccion: null }', (await api('GET', '/api/direcciones/predeterminada', null, T.maria)).status === 404);
    const dirMaria = (await api('POST', '/api/direcciones', { direccion: 'Calle Bolívar 7', latitud: -0.21, longitud: -78.49 }, T.maria)).body.direccion.id;
    for (const [cuerpo, quehay] of [[{ latitud: 1, longitud: 1 }, 'falta la dirección'], [{ direccion: 'X', latitud: 200, longitud: 1 }, 'latitud fuera de rango'], [{ direccion: 'X', latitud: 1 }, 'falta la longitud']]) {
      check(`validación: ${quehay} -> 400`, (await api('POST', '/api/direcciones', cuerpo, T.carlos)).status === 400);
    }
    check('SEGURIDAD: modificar o borrar la dirección de otro usuario -> 404', (await api('PUT', `/api/direcciones/${dirMaria}`, { nombre: 'Hack' }, T.carlos)).status === 404 && (await api('DELETE', `/api/direcciones/${dirMaria}`, null, T.carlos)).status === 404);
    r = await api('PUT', `/api/direcciones/${dirCarlos2}`, { nombre: 'Trabajo', referencia: 'Piso 3' }, T.carlos);
    check('actualizar la propia dirección: 200', r.status === 200 && r.body.direccion.nombre === 'Trabajo');
    check('eliminar la propia dirección: 200 y desaparece (borrado lógico)', (await api('DELETE', `/api/direcciones/${dirCarlos2}`, null, T.carlos)).status === 200 && (await api('GET', '/api/direcciones', null, T.carlos)).body.direcciones.length === 1 && (await q('SELECT eliminadoen FROM direcciones WHERE direccion=$1', [dirCarlos2]))[0].eliminadoen !== null);

    seccion('2. Crear pedido');
    r = await api('POST', '/api/pedidos', { productos: [{ productoId: pizza, cantidad: 2 }, { productoId: agua, cantidad: 1, notas: 'Sin hielo' }], metodoPago: 'efectivo', direccionEntregaId: dirCarlos, notasCliente: 'Sin cebolla' }, T.carlos);
    const P1 = r.body.pedido?.id; const p1 = r.body.pedido || {};
    check('crear: 201, id PED-AAAAMMDD-000001, estado "pendiente", negocio deducido de los productos', r.status === 201 && /^PED-\d{8}-\d{6}$/.test(P1) && p1.estado === 'pendiente' && p1.vendedorId === venLuis && p1.clienteId === 'cruiz', JSON.stringify(r.body).slice(0, 160));
    check('totales calculados por el servidor: subtotal 12.00, envío 0, total 12.00, método "efectivo"', p1.subtotal === 12 && p1.costoDelivery === 0 && p1.total === 12 && p1.metodoPago === 'efectivo');
    check('detalles con copia del nombre y del precio al momento de comprar', p1.detalles?.length === 2 && p1.detalles[0].nombre === 'Pizza Margarita' && p1.detalles[0].precioUnitario === 5.5 && p1.detalles[0].subtotal === 11 && p1.detalles[1].notas === 'Sin hielo');
    check('la dirección de entrega queda COPIADA en el pedido', p1.direccionEntrega?.direccion === 'Av. Amazonas N1-23' && p1.direccionEntrega.latitud === -0.18);
    check('stock descontado: pizza 10 -> 8; el agua (sin control de stock) no cambia', (await stock(pizza)).stock === 8 && (await q('SELECT stock FROM productos WHERE producto=$1', [agua]))[0].stock === 0);
    check('notificación al vendedor guardada (la del cliente solo va por socket)', (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='lmora' AND tipo='pedido_nuevo' AND pedido=$1", [P1]))[0].n === 1 && (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='cruiz'"))[0].n === 0);
    r = await api('POST', '/api/pedidos', { productos: [{ productoId: pizza, cantidad: 1 }, { productoId: pizza, cantidad: 2 }], metodoPago: 'EFECTIVO' }, T.carlos);
    const P2 = r.body.pedido?.id;
    check('el mismo producto repetido se suma en una línea (1 + 2 = 3) y acepta "EFECTIVO"', r.status === 201 && r.body.pedido.detalles.length === 1 && r.body.pedido.detalles[0].cantidad === 3 && r.body.pedido.total === 16.5 && (await stock(pizza)).stock === 5);

    seccion('3. Crear pedido: validaciones y seguridad');
    const mal = async (cuerpo, esperado, quehay, extra) => {
      const x = await api('POST', '/api/pedidos', { metodoPago: 'efectivo', ...cuerpo }, T.carlos);
      check(`${quehay}: ${esperado}${extra ? ` ${extra}` : ''}`, x.status === esperado && (!extra || x.body.code === extra), `${x.status} ${JSON.stringify(x.body).slice(0, 110)}`);
      return x;
    };
    await mal({ productos: [] }, 400, 'sin productos');
    await mal({ productos: [{ productoId: 'abc', cantidad: 1 }] }, 400, 'producto con id mal formado');
    await mal({ productos: [{ productoId: pizza, cantidad: 0 }] }, 400, 'cantidad 0');
    await mal({ productos: [{ productoId: pizza, cantidad: 100 }] }, 400, 'cantidad 100 (máximo 99)');
    await mal({ productos: [{ productoId: 'PRO-999999', cantidad: 1 }] }, 404, 'producto inexistente');
    await mal({ productos: [{ productoId: pizza, cantidad: 1 }, { productoId: cafe, cantidad: 1 }] }, 400, 'productos de dos negocios distintos', 'NEGOCIOSMEZCLADOS');
    await mal({ productos: [{ productoId: pizza, cantidad: 1 }], vendedorId: venAna }, 400, 'vendedorId que no corresponde a los productos', 'NEGOCIOINCORRECTO');
    await mal({ productos: [{ productoId: pizza, cantidad: 1 }], metodoPago: 'bitcoin' }, 400, 'método de pago inexistente');
    await mal({ productos: [{ productoId: pizza, cantidad: 1 }], direccionEntregaId: dirMaria }, 404, 'SEGURIDAD: dirección de otro usuario');
    r = await mal({ productos: [{ productoId: flan, cantidad: 3 }] }, 400, 'más unidades que el stock', 'STOCK_INSUFICIENTE');
    check('...y el error trae disponible=2, solicitado=3 y el productoId (como esperaba la app)', r.body.disponible === 2 && r.body.solicitado === 3 && r.body.productoId === flan);
    await api('PATCH', `/api/productos/${jugo}/disponible`, { disponible: false }, T.luis);
    await mal({ productos: [{ productoId: jugo, cantidad: 1 }] }, 409, 'producto marcado como no disponible', 'PRODUCTONODISPONIBLE');
    await db_update(q, "UPDATE vendedores SET aceptapedidos=false WHERE vendedor=$1", [venLuis]);
    await mal({ productos: [{ productoId: pizza, cantidad: 1 }] }, 409, 'negocio que no acepta pedidos', 'NEGOCIONODISPONIBLE');
    await db_update(q, "UPDATE vendedores SET aceptapedidos=true WHERE vendedor=$1", [venLuis]);
    await db_update(q, "UPDATE vendedores SET aprobacion='001' WHERE vendedor=$1", [venAna]);
    await mal({ productos: [{ productoId: cafe, cantidad: 1 }] }, 409, 'negocio no aprobado', 'NEGOCIONODISPONIBLE');
    await db_update(q, "UPDATE vendedores SET aprobacion='002' WHERE vendedor=$1", [venAna]);
    check('un vendedor no puede crear pedidos (403) y sin token da 401', (await api('POST', '/api/pedidos', { productos: [{ productoId: pizza, cantidad: 1 }], metodoPago: 'efectivo' }, T.luis)).status === 403 && (await api('POST', '/api/pedidos', {})).status === 401);
    check('ningún pedido inválido descontó stock (pizza sigue en 5)', (await stock(pizza)).stock === 5);

    seccion('4. Listados y acceso a un pedido (antes cualquiera podía ver cualquier pedido)');
    r = await api('GET', '/api/pedidos/mis-pedidos', null, T.carlos);
    check('mis-pedidos: 2 pedidos con paginación', r.status === 200 && r.body.pedidos.length === 2 && r.body.pagination.total === 2 && r.body.pedidos[0].detalles.length >= 1);
    r = await api('GET', '/api/pedidos/mis-pedidos?limit=1', null, T.carlos);
    check('paginación ?limit=1: 1 pedido y hasNext=true', r.body.pedidos.length === 1 && r.body.pagination.hasNext === true);
    check('otro cliente no ve pedidos ajenos', (await api('GET', '/api/pedidos/mis-pedidos', null, T.maria)).body.pedidos.length === 0);
    r = await api('GET', '/api/pedidos/vendedor/pedidos', null, T.luis);
    check('vendedor/pedidos: los 2 pedidos de su negocio, con el cliente', r.status === 200 && r.body.pedidos.length === 2 && r.body.pedidos[0].cliente.nombre === 'Carlos');
    check('otro vendedor ve 0 pedidos · un cliente no entra a esa ruta (403)', (await api('GET', '/api/pedidos/vendedor/pedidos', null, T.ana)).body.pedidos.length === 0 && (await api('GET', '/api/pedidos/vendedor/pedidos', null, T.carlos)).status === 403);
    r = await api('GET', `/api/pedidos/${P1}`, null, T.carlos);
    check('GET /:id del cliente dueño: 200 con el pedido (sin envoltorio, como antes)', r.status === 200 && r.body.id === P1 && r.body.vendedor.nombreNegocio === 'Pizzería Luis');
    check('PRIVACIDAD: el pedido no expone correos de nadie', !JSON.stringify(r.body).includes('@test.com'));
    check('SEGURIDAD: otro cliente -> 404 · otro vendedor -> 404 · repartidor sin asignar -> 404', (await api('GET', `/api/pedidos/${P1}`, null, T.maria)).status === 404 && (await api('GET', `/api/pedidos/${P1}`, null, T.ana)).status === 404 && (await api('GET', `/api/pedidos/${P1}`, null, T.pedro)).status === 404);
    check('el vendedor dueño sí lo ve · id mal formado: 400 · inexistente: 404 · sin token: 401', (await api('GET', `/api/pedidos/${P1}`, null, T.luis)).status === 200 && (await api('GET', '/api/pedidos/abc', null, T.luis)).status === 400 && (await api('GET', '/api/pedidos/PED-20200101-999999', null, T.luis)).status === 404 && (await api('GET', `/api/pedidos/${P1}`)).status === 401);

    seccion('5. Flujo del vendedor (máquina de estados)');
    const est = (id, estado, token = T.luis, extra = {}) => api('PUT', `/api/pedidos/${id}/estado`, { estado, ...extra }, token);
    check('saltar de pendiente a listo: 409 TRANSICIONINVALIDA', (await est(P1, 'listo')).body.code === 'TRANSICIONINVALIDA');
    check('estado inválido ("entregado") 400 · un cliente no puede cambiar estados 403 · otro vendedor 404', (await est(P1, 'entregado')).status === 400 && (await est(P1, 'confirmado', T.carlos)).status === 403 && (await est(P1, 'confirmado', T.ana)).status === 404);
    r = await est(P1, 'confirmado');
    check('confirmar: 200, estado "confirmado" y fecha de confirmación', r.status === 200 && r.body.estado === 'confirmado' && r.body.fechaConfirmacion);
    check('retroceder (confirmado -> pendiente/confirmado) es imposible: 409', (await est(P1, 'confirmado')).status === 409);
    check('preparando: 200', (await est(P1, 'preparando')).body.estado === 'preparando');
    await db_update(q, "UPDATE repartidores SET disponible=true WHERE usuario='pruiz'");
    r = await est(P1, 'listo');
    check('listo: 200 con fecha', r.status === 200 && r.body.estado === 'listo' && r.body.fechaListo);
    check('al quedar listo se avisa al cliente y SOLO a los repartidores disponibles (Pedro sí, Rosa no)', (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='cruiz' AND tipo='pedido_listo'"))[0].n === 1 && (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='pruiz' AND tipo='pedido_listo'"))[0].n === 1 && (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='rvega' AND tipo='pedido_listo'"))[0].n === 0);
    r = await api('GET', `/api/pedidos/${P1}`, null, T.pedro);
    check('un repartidor aprobado ve un pedido LISTO sin asignar, pero SIN el teléfono del cliente', r.status === 200 && r.body.cliente.telefono === undefined && r.body.direccionEntrega.direccion === 'Av. Amazonas N1-23');
    check('otro cliente sigue sin verlo', (await api('GET', `/api/pedidos/${P1}`, null, T.maria)).status === 404);

    seccion('6. Repartidor: aceptar (con carrera), recoger y entregar');
    const acepta = (id, token, costo) => api('PATCH', `/api/pedidos/${id}/aceptar-repartidor`, costo === undefined ? {} : { costoDelivery: costo }, token);
    check('sin costo -> 400 · costo 101 -> 400 · costo negativo -> 400', (await acepta(P1, T.pedro)).status === 400 && (await acepta(P1, T.pedro, 101)).status === 400 && (await acepta(P1, T.pedro, -1)).status === 400);
    check('un cliente no puede aceptar (403)', (await acepta(P1, T.carlos, 2)).status === 403);
    await db_update(q, "UPDATE repartidores SET aprobacion='001' WHERE usuario='pruiz'");
    check('repartidor NO aprobado: 403', (await acepta(P1, T.pedro, 2)).body.code === 'REPARTIDORNOAPROBADO');
    await db_update(q, "UPDATE repartidores SET aprobacion='002' WHERE usuario='pruiz'");
    const [a1, a2] = await Promise.all([acepta(P1, T.pedro, 2.5), acepta(P1, T.rosa, 3)]);
    const gano = a1.status === 200 ? { nom: 'pedro', rep: repPedro, tok: T.pedro, costo: 2.5, res: a1 } : { nom: 'rosa', rep: repRosa, tok: T.rosa, costo: 3, res: a2 };
    const perdio = a1.status === 200 ? { rep: repRosa, tok: T.rosa, res: a2 } : { rep: repPedro, tok: T.pedro, res: a1 };
    check('CARRERA: dos repartidores aceptan a la vez -> exactamente UNO gana (200) y el otro recibe 409 PEDIDOASIGNADO', [a1.status, a2.status].sort().join() === '200,409' && perdio.res.body.code === 'PEDIDOASIGNADO', `${a1.status},${a2.status}`);
    const pg = gano.res.body.pedido;
    check('el ganador queda asignado: estado "en_camino", repartidorId, envío y total = subtotal + envío', pg.estado === 'en_camino' && pg.repartidorId === gano.rep && pg.costoDelivery === gano.costo && pg.total === 12 + gano.costo && pg.fechaAsignacion);
    check('el repartidor queda "en servicio"', (await q('SELECT enservicio e FROM repartidores WHERE repartidor=$1', [gano.rep]))[0].e === true);
    check('se avisó al cliente: "repartidor asignado" (en_camino)', (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='cruiz' AND tipo='pedido_en_camino'"))[0].n === 1);
    check('el repartidor asignado ve el pedido con el teléfono del cliente', (await api('GET', `/api/pedidos/${P1}`, null, gano.tok)).body.cliente.telefono !== undefined);
    check('el que perdió ya no puede verlo (404) ni recogerlo (404)', (await api('GET', `/api/pedidos/${P1}`, null, perdio.tok)).status === 404 && (await api('PATCH', `/api/pedidos/${P1}/recogido`, null, perdio.tok)).status === 404);
    check('entregar sin haberlo recogido: 409 · el cliente marcar recibido ahora: 409', (await api('PATCH', `/api/pedidos/${P1}/entregado`, null, gano.tok)).status === 409 && (await api('PATCH', `/api/pedidos/${P1}/recibido`, null, T.carlos)).status === 409);
    check('/en-camino (ruta heredada) con el pedido ya en camino: 200', (await api('PATCH', `/api/pedidos/${P1}/en-camino`, null, gano.tok)).status === 200);
    r = await api('PATCH', `/api/pedidos/${P1}/recogido`, null, gano.tok);
    check('recoger: 200, estado "recogido" y fecha de recogida', r.status === 200 && r.body.pedido.estado === 'recogido' && r.body.pedido.fechaRecogida);
    check('recoger dos veces: 409', (await api('PATCH', `/api/pedidos/${P1}/recogido`, null, gano.tok)).status === 409);
    check('entregar: 200 y el repartidor sale de "en servicio"', (await api('PATCH', `/api/pedidos/${P1}/entregado`, null, gano.tok)).status === 200 && (await q('SELECT enservicio e FROM repartidores WHERE repartidor=$1', [gano.rep]))[0].e === false);
    check('otro cliente no puede marcar recibido (404)', (await api('PATCH', `/api/pedidos/${P1}/recibido`, null, T.maria)).status === 404);
    r = await api('PATCH', `/api/pedidos/${P1}/recibido`, null, T.carlos);
    check('el cliente confirma: 200, estado "recibido_cliente"', r.status === 200 && r.body.pedido.estado === 'recibido_cliente' && r.body.pedido.fechaRecibido);
    check('marcar recibido dos veces: 409', (await api('PATCH', `/api/pedidos/${P1}/recibido`, null, T.carlos)).status === 409);
    check('contadores: negocio +1 pedido, repartidor +1 completado, pizza +2 vendidas, agua +1', (await q('SELECT totalpedidos n FROM vendedores WHERE vendedor=$1', [venLuis]))[0].n === 1 && (await q('SELECT pedidoscompletos n FROM repartidores WHERE repartidor=$1', [gano.rep]))[0].n === 1 && (await q('SELECT totalvendidos n FROM productos WHERE producto=$1', [pizza]))[0].n === 2 && (await q('SELECT totalvendidos n FROM productos WHERE producto=$1', [agua]))[0].n === 1);
    check('notificaciones del flujo: cliente (en_camino, recogido, entregado), vendedor y repartidor (recibido)', (await q("SELECT string_agg(tipo, ',' ORDER BY id) s FROM notificaciones WHERE usuario='cruiz' AND tipo IN ('pedido_en_camino','pedido_recogido','pedido_entregado')"))[0].s === 'pedido_en_camino,pedido_recogido,pedido_entregado' && (await q("SELECT count(*)::int n FROM notificaciones WHERE tipo='pedido_recibido_cliente' AND pedido=$1", [P1]))[0].n === 2);

    seccion('7. Seguimiento y versionado automáticos (los hace la base de datos)');
    check('SEGUIMIENTOPEDIDO guarda TODA la secuencia de estados', (await q("SELECT string_agg(coalesce(estadoanterior,'-')||'>'||estadonuevo, ',' ORDER BY id) s FROM seguimientopedido WHERE pedido=$1", [P1]))[0].s === '->001,001>002,002>003,003>004,004>005,005>006,006>007,007>008');
    check('HISTPEDIDOS guarda cada versión (7 cambios) con quién la hizo', (await q('SELECT count(*)::int n FROM histpedidos WHERE pedido=$1', [P1]))[0].n >= 7 && (await q("SELECT count(*)::int n FROM histpedidos WHERE pedido=$1 AND cambiadopor='lmora'", [P1]))[0].n >= 2);

    seccion('8. Calificar');
    check('calificar un pedido que aún no se entregó: 409', (await api('POST', `/api/pedidos/${P2}/calificar`, { valoracion: 5 }, T.carlos)).body.code === 'PEDIDONOENTREGADO');
    check('valoración 6 -> 400 · otro cliente -> 404', (await api('POST', `/api/pedidos/${P1}/calificar`, { valoracion: 6 }, T.carlos)).status === 400 && (await api('POST', `/api/pedidos/${P1}/calificar`, { valoracion: 5 }, T.maria)).status === 404);
    r = await api('POST', `/api/pedidos/${P1}/calificar`, { valoracion: 5, comentario: 'Excelente' }, T.carlos);
    check('calificar al negocio (como envía la app): 200', r.status === 200);
    check('calificar dos veces lo mismo: 409 YACALIFICADO', (await api('POST', `/api/pedidos/${P1}/calificar`, { valoracion: 4 }, T.carlos)).body.code === 'YACALIFICADO');
    check('calificar al repartidor (tipo "repartidor"): 200', (await api('POST', `/api/pedidos/${P1}/calificar`, { valoracion: 4, tipo: 'repartidor' }, T.carlos)).status === 200);
    check('el promedio del negocio (5.00) y del repartidor (4.00) se recalcula', Number((await q('SELECT calificacion c FROM vendedores WHERE vendedor=$1', [venLuis]))[0].c) === 5 && (await q('SELECT totalcalif n FROM vendedores WHERE vendedor=$1', [venLuis]))[0].n === 1 && Number((await q('SELECT calificacion c FROM repartidores WHERE repartidor=$1', [gano.rep]))[0].c) === 4);

    seccion('9. Cancelar y rechazar (el stock vuelve)');
    check('otro cliente no puede cancelar mi pedido: 404', (await api('PUT', `/api/pedidos/${P2}/cancelar`, null, T.maria)).status === 404);
    r = await api('PUT', `/api/pedidos/${P2}/cancelar`, { motivo: 'Me equivoqué' }, T.carlos);
    check('cancelar un pedido pendiente: 200 y las 3 pizzas vuelven al stock (5 -> 8)', r.status === 200 && (await stock(pizza)).stock === 8 && (await estadoDe(P2)) === '010');
    check('queda quién y por qué canceló; el vendedor recibe el aviso', (await q('SELECT canceladopor c, motivocancel m FROM pedidos WHERE pedido=$1', [P2]))[0].c === 'cruiz' && (await q("SELECT count(*)::int n FROM notificaciones WHERE usuario='lmora' AND tipo='pedido_cancelado' AND pedido=$1", [P2]))[0].n === 1);
    check('cancelar otra vez: 409', (await api('PUT', `/api/pedidos/${P2}/cancelar`, null, T.carlos)).status === 409);
    const P3 = (await api('POST', '/api/pedidos', { productos: [{ productoId: agua, cantidad: 1 }], metodoPago: 'efectivo' }, T.carlos)).body.pedido.id;
    await est(P3, 'confirmado');
    check('cancelar un pedido YA confirmado: 409 PEDIDOENPROCESO', (await api('PUT', `/api/pedidos/${P3}/cancelar`, null, T.carlos)).body.code === 'PEDIDOENPROCESO');
    const P4 = (await api('POST', '/api/pedidos', { productos: [{ productoId: pizza, cantidad: 1 }], metodoPago: 'efectivo' }, T.carlos)).body.pedido.id;
    r = await est(P4, 'rechazado', T.luis, { motivo: 'Sin ingredientes' });
    check('el vendedor rechaza un pedido pendiente: 200, estado "rechazado", stock devuelto', r.status === 200 && r.body.estado === 'rechazado' && (await stock(pizza)).stock === 8 && (await q('SELECT motivocancel m FROM pedidos WHERE pedido=$1', [P4]))[0].m === 'Sin ingredientes');
    check('...y avisa al cliente con el motivo', (await q("SELECT mensaje m FROM notificaciones WHERE usuario='cruiz' AND tipo='pedido_rechazado'"))[0].m.includes('Sin ingredientes'));
    check('un pedido ya confirmado NO se puede rechazar (409)', (await est(P3, 'rechazado')).status === 409);
    const P5 = (await api('POST', '/api/pedidos', { productos: [{ productoId: flan, cantidad: 2 }], metodoPago: 'efectivo' }, T.carlos)).body.pedido.id;
    check('al pedir todo el stock el producto pasa solo a AGOTADO (002)', (await stock(flan)).estado === '002' && (await stock(flan)).stock === 0);
    await api('PUT', `/api/pedidos/${P5}/cancelar`, null, T.carlos);
    check('...y al cancelar vuelve a DISPONIBLE (001) con su stock', (await stock(flan)).estado === '001' && (await stock(flan)).stock === 2);

    seccion('10. Notificaciones y dispositivos (push)');
    r = await api('GET', '/api/notificaciones', null, T.luis);
    const n0 = r.body.notificaciones?.[0];
    check('listar: notificaciones del usuario con total y no leídas, ids numéricos', r.status === 200 && r.body.notificaciones.length >= 3 && typeof n0.id === 'number' && r.body.noLeidas >= 3 && r.body.notificaciones.every((n) => n.usuarioId === 'lmora'));
    const antes = r.body.noLeidas;
    check('marcar como leída: 200 y baja el contador', (await api('PATCH', `/api/notificaciones/${n0.id}/leida`, null, T.luis)).status === 200 && (await api('GET', '/api/notificaciones', null, T.luis)).body.noLeidas === antes - 1);
    check('SEGURIDAD: marcar la notificación de otro usuario -> 404 · id inválido -> 400', (await api('PATCH', `/api/notificaciones/${n0.id}/leida`, null, T.carlos)).status === 404 && (await api('PATCH', '/api/notificaciones/abc/leida', null, T.luis)).status === 400);
    check('registrar el token push del celular: 200', (await api('POST', '/api/notificaciones/dispositivo', { token: 'token-fcm-prueba-123', plataforma: 'android' }, T.luis)).status === 200 && (await q("SELECT usuario u, plataforma p, activo a FROM dispositivos WHERE tokenfcm='token-fcm-prueba-123'"))[0].u === 'lmora');
    await api('POST', '/api/notificaciones/dispositivo', { token: 'token-fcm-prueba-123', plataforma: 'ios' }, T.carlos);
    check('el mismo token en otro usuario se REASIGNA (un token = un usuario)', (await q("SELECT count(*)::int n FROM dispositivos WHERE tokenfcm='token-fcm-prueba-123'"))[0].n === 1 && (await q("SELECT usuario u FROM dispositivos WHERE tokenfcm='token-fcm-prueba-123'"))[0].u === 'cruiz');
    check('plataforma inválida -> 400 · sin token -> 400 · quitar el dispositivo -> 200', (await api('POST', '/api/notificaciones/dispositivo', { token: 'x', plataforma: 'nokia' }, T.luis)).status === 400 && (await api('POST', '/api/notificaciones/dispositivo', {}, T.luis)).status === 400 && (await api('DELETE', '/api/notificaciones/dispositivo', { token: 'token-fcm-prueba-123' }, T.carlos)).status === 200);

    seccion('11. Seguimiento en tiempo real (sockets)');
    const P6 = (await api('POST', '/api/pedidos', { productos: [{ productoId: agua, cantidad: 1 }], metodoPago: 'efectivo' }, T.carlos)).body.pedido.id;
    await est(P6, 'confirmado'); await est(P6, 'preparando'); await est(P6, 'listo');
    const sCarlos = await conectar(T.carlos); const sMaria = await conectar(T.maria); const sPedro = await conectar(T.pedro);
    check('conexión sin token válido: se rechaza', !!(await conectar('token-falso')).error);
    check('el cliente dueño entra a la sala del pedido', (await emitir(sCarlos, 'pedido:join', { pedidoId: P6 })).ok === true);
    check('SEGURIDAD: otro cliente NO entra (NO_AUTORIZADO) · pedido inexistente (PEDIDO_NO_EXISTE)', (await emitir(sMaria, 'pedido:join', { pedidoId: P6 })).error === 'NO_AUTORIZADO' && (await emitir(sCarlos, 'pedido:join', { pedidoId: 'PED-20200101-999999' })).error === 'PEDIDO_NO_EXISTE');
    check('SEGURIDAD: un repartidor sin asignar no puede enviar ubicación (NO_AUTORIZADO)', (await emitir(sPedro, 'repartidor:ubicacion', { pedidoId: P6, lat: -0.18, lng: -78.47 })).error === 'NO_AUTORIZADO');
    await acepta(P6, T.pedro, 2);
    await dormir(2100);                                   // el intento anterior (rechazado) también cuenta para el límite de 2 s
    const recibida = esperar(sCarlos, 'pedido:ubicacion');
    check('el repartidor asignado envía su ubicación', (await emitir(sPedro, 'repartidor:ubicacion', { pedidoId: P6, lat: -0.19, lng: -78.48, speed: 5, heading: 90 })).ok === true);
    const u = await recibida;
    check('el cliente la recibe EN VIVO por la sala del pedido', u && u.lat === -0.19 && u.lng === -78.48 && u.source === 'live');
    await dormir(400);
    check('la ubicación se guarda en la BD: posición actual del repartidor e historial', Number((await q('SELECT latitud l FROM repartidores WHERE repartidor=$1', [repPedro]))[0].l) === -0.19 && (await q('SELECT count(*)::int n FROM ubicacionrepartidor WHERE pedido=$1', [P6]))[0].n === 1);
    check('límite: otra ubicación antes de 2 s -> MUY_FRECUENTE_2S', (await emitir(sPedro, 'repartidor:ubicacion', { pedidoId: P6, lat: -0.19, lng: -78.48 })).error === 'MUY_FRECUENTE_2S');
    await dormir(2100);
    check('coordenadas inválidas -> LATLNG_INVALIDO · un cliente no puede enviar ubicación (SOLO_REPARTIDOR)', (await emitir(sPedro, 'repartidor:ubicacion', { pedidoId: P6, lat: 999, lng: 0 })).error === 'LATLNG_INVALIDO' && (await emitir(sCarlos, 'repartidor:ubicacion', { pedidoId: P6, lat: 0, lng: 0 })).error === 'SOLO_REPARTIDOR');
    const aviso = esperar(sCarlos, 'notificacion');
    await api('PATCH', `/api/pedidos/${P6}/recogido`, null, T.pedro);
    const nota = await aviso;
    check('al cambiar el estado el cliente recibe la notificación por socket (tipo pedido_recogido)', nota && nota.tipo === 'pedido_recogido' && nota.pedidoId === P6 && nota.estado === 'recogido');
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();

// Cambios directos en la BD de pruebas (simulan que un administrador toca datos)
async function db_update(q, sql, params) { await q(sql, params); }
