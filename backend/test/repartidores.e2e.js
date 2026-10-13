// Prueba de extremo a extremo de REPARTIDORES.  Uso:  npm run test:repartidores
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3096, bd: 'vallexpress_repartidores' });
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
    const rosa = await t.registrar('rosa@test.com', 'Rosa', 'Vega', 'repartidor', { vehiculo: 'Auto', placa: 'CD5678' });
    const T = { luis: luis.token, ana: ana.token, carlos: carlos.token, maria: maria.token, pedro: pedro.token, rosa: rosa.token };
    const repPedro = (await q("SELECT cusuario r FROM trepartidores WHERE cusuario='pruiz' AND fhasta>now()"))[0].r;
    const repRosa = (await q("SELECT cusuario r FROM trepartidores WHERE cusuario='rvega' AND fhasta>now()"))[0].r;
    const dir = (await api('POST', '/api/direcciones', { nombre: 'Casa', direccion: 'Av. Amazonas N1-23', latitud: -0.18, longitud: -78.47 }, T.carlos)).body.direccion.id;
    const pizza = (await api('POST', '/api/productos', { nombre: 'Pizza Margarita', precio: 5.5, stock: 20 }, T.luis)).body.producto.id;
    const est = (id, estado) => api('PUT', `/api/pedidos/${id}/estado`, { estado }, T.luis);
    const hist = async () => (await q('SELECT count(*)::int n FROM trepartidores WHERE cusuario=$1 AND fhasta<now()', [repPedro]))[0].n;
    // Un pedido del cliente; con hastaListo=true lo deja LISTO (sin repartidor)
    const pedido = async (hastaListo = true) => {
      const id = (await api('POST', '/api/pedidos', { productos: [{ productoId: pizza, cantidad: 1 }], metodoPago: 'efectivo', direccionEntregaId: dir }, T.carlos)).body.pedido.id;
      await est(id, 'confirmado');
      if (hastaListo) { await est(id, 'preparando'); await est(id, 'listo'); }
      return id;
    };
    let r;

    seccion('1. Perfil del repartidor');
    r = await api('GET', '/api/repartidores/perfil/mi-perfil', null, T.pedro);
    const mp = r.body.repartidor || {};
    check('mi-perfil: id = usuario (pruiz), vehículo "Motocicleta" (001), placa, sin licencia, sin foto, aprobado', r.status === 200 && mp.id === 'pruiz' && mp.vehiculo === 'Motocicleta' && mp.vehiculoCodigo === '001' && mp.placa === 'AB1234' && mp.licencia === null && mp.foto === null && mp.aprobacion === '002', JSON.stringify(mp).slice(0, 200));
    check('el propio repartidor ve su correo y teléfono', mp.usuario?.email === 'pedro@test.com');
    check('un cliente no entra (403) · sin token (401)', (await api('GET', '/api/repartidores/perfil/mi-perfil', null, T.carlos)).status === 403 && (await api('GET', '/api/repartidores/perfil/mi-perfil')).status === 401);
    r = await api('PUT', '/api/repartidores/perfil/actualizar', { vehiculo: 'Auto', placa: 'abc-123', licencia: 'abc12345' }, T.pedro);
    check('actualizar: vehículo "Automovil" (002), placa normalizada ABC123, licencia en mayúsculas', r.status === 200 && r.body.repartidor.vehiculo === 'Automovil' && r.body.repartidor.vehiculoCodigo === '002' && r.body.repartidor.placa === 'ABC123' && r.body.repartidor.licencia === 'ABC12345', JSON.stringify(r.body).slice(0, 160));
    r = await api('PUT', '/api/repartidores/perfil/actualizar', { vehiculo: 'Patineta' }, T.pedro);
    check('vehículo que no está en el catálogo: se devuelve igual ("Patineta") y se guarda sin código + texto original', r.body.repartidor.vehiculo === 'Patineta' && r.body.repartidor.vehiculoCodigo === null && (await q("SELECT datosextra d FROM trepartidores WHERE cusuario=$1 AND fhasta>now()", [repPedro]))[0].d === 'vehiculo=Patineta');
    r = await api('PUT', '/api/repartidores/perfil/actualizar', { vehiculo: 'Moto' }, T.pedro);
    check('al volver a un vehículo del catálogo se limpia el texto extra', r.body.repartidor.vehiculo === 'Motocicleta' && (await q('SELECT datosextra d FROM trepartidores WHERE cusuario=$1 AND fhasta>now()', [repPedro]))[0].d === null);
    check('placa inválida -> 400 · placa de otro repartidor -> 409 · vehículo de 1 letra -> 400', (await api('PUT', '/api/repartidores/perfil/actualizar', { placa: 'ZZ' }, T.pedro)).status === 400 && (await api('PUT', '/api/repartidores/perfil/actualizar', { placa: 'CD5678' }, T.pedro)).body.code === 'PLACADUPLICADA' && (await api('PUT', '/api/repartidores/perfil/actualizar', { vehiculo: 'a' }, T.pedro)).status === 400);
    check('crear perfil: datos inválidos -> 400 · ya tiene perfil -> 409', (await api('POST', '/api/repartidores', { placa: 'EF9012' }, T.pedro)).status === 400 && (await api('POST', '/api/repartidores', { vehiculo: 'Moto', placa: 'EF9012' }, T.pedro)).status === 409);
    r = await api('PATCH', '/api/repartidores/perfil/foto', { foto: await t.imagen(700, 700) }, T.pedro);
    check('foto de perfil: 200 con URL /uploads/perfil/..._m.webp', r.status === 200 && /\/uploads\/perfil\/[0-9a-f]{24}_m\.webp$/.test(r.body.foto), JSON.stringify(r.body).slice(0, 120));
    check('el perfil devuelve esa foto y REPARTIDORES.FOTO guarda el código ARC-', (await api('GET', '/api/repartidores/perfil/mi-perfil', null, T.pedro)).body.repartidor.foto === r.body.foto && /^ARC-/.test((await q('SELECT foto f FROM trepartidores WHERE cusuario=$1 AND fhasta>now()', [repPedro]))[0].f));
    check('foto inválida -> 400 · sin foto -> 400', (await api('PATCH', '/api/repartidores/perfil/foto', { foto: 'basura' }, T.pedro)).status === 400 && (await api('PATCH', '/api/repartidores/perfil/foto', {}, T.pedro)).status === 400);
    check('los cambios del perfil quedan versionados en HISTREPARTIDORES', (await hist()) >= 4);

    seccion('2. Disponibilidad');
    r = await api('PUT', '/api/repartidores/disponibilidad', { disponible: true }, T.pedro);
    check('activar disponibilidad: 200', r.status === 200 && r.body.repartidor.disponible === true && (await q("SELECT disponible d FROM trepartidores WHERE cusuario=$1 AND fhasta>now()", [repPedro]))[0].d === true);
    check('valor no booleano -> 400 · falta el campo -> 400', (await api('PUT', '/api/repartidores/disponibilidad', { disponible: 'quizas' }, T.pedro)).status === 400 && (await api('PUT', '/api/repartidores/disponibilidad', {}, T.pedro)).status === 400);
    check('PATCH /estado (ruta que la app usaba y no existía): "ocupado" -> no disponible; "disponible" -> disponible', (await api('PATCH', '/api/repartidores/estado', { estado: 'ocupado' }, T.pedro)).body.repartidor.disponible === false && (await api('PATCH', '/api/repartidores/estado', { estado: 'disponible' }, T.pedro)).body.repartidor.disponible === true);
    check('estado desconocido -> 400', (await api('PATCH', '/api/repartidores/estado', { estado: 'xx' }, T.pedro)).status === 400);
    await q("UPDATE trepartidores SET aprobacion='001' WHERE cusuario=$1 AND fhasta>now()", [repRosa]);
    check('un repartidor NO aprobado no puede activarse (403) pero sí desactivarse (200)', (await api('PUT', '/api/repartidores/disponibilidad', { disponible: true }, T.rosa)).body.code === 'REPARTIDORNOAPROBADO' && (await api('PUT', '/api/repartidores/disponibilidad', { disponible: false }, T.rosa)).status === 200);

    seccion('3. Pedidos desde el punto de vista del repartidor');
    const A = await pedido(true);                 // listo, sin repartidor
    const B = await pedido(false);                // solo confirmado
    r = await api('GET', '/api/repartidores/pendientes', null, T.pedro);
    const pa = r.body.pedidos?.find((x) => x.id === A);
    check('pendientes: el pedido LISTO con negocio, dirección de entrega y detalles', r.status === 200 && pa && pa.vendedor.nombreNegocio === 'Pizzería Luis' && pa.direccionEntrega.direccion === 'Av. Amazonas N1-23' && pa.detalles.length === 1 && !r.body.pedidos.some((x) => x.id === B));
    check('PRIVACIDAD: antes de aceptar NO se ve el teléfono del cliente', pa.cliente.telefono === undefined && pa.cliente.nombre === 'Carlos');
    check('/pedidos-disponibles (nombre que usa la app) da lo mismo', (await api('GET', '/api/repartidores/pedidos-disponibles', null, T.pedro)).body.pedidos.some((x) => x.id === A));
    r = await api('GET', '/api/repartidores/pedidos-vista', null, T.pedro);
    check('pedidos-vista: solo los que se están preparando (el confirmado sí, el listo no)', r.status === 200 && r.body.pedidos.some((x) => x.id === B) && !r.body.pedidos.some((x) => x.id === A));
    check('un repartidor no aprobado (403) · un cliente (403) · sin token (401) no ven pedidos', (await api('GET', '/api/repartidores/pendientes', null, T.rosa)).status === 403 && (await api('GET', '/api/repartidores/pendientes', null, T.carlos)).status === 403 && (await api('GET', '/api/repartidores/pendientes')).status === 401);
    await q("UPDATE trepartidores SET aprobacion='002' WHERE cusuario=$1 AND fhasta>now()", [repRosa]);
    const aceptar = (id, token, costo) => api('POST', `/api/repartidores/pedidos/${id}/aceptar`, costo === undefined ? {} : { costoDelivery: costo }, token);
    check('aceptar: sin costo, negativo o mayor a 100 -> 400 · id mal formado -> 400 · un cliente -> 403', (await aceptar(A, T.pedro)).status === 400 && (await aceptar(A, T.pedro, -1)).status === 400 && (await aceptar(A, T.pedro, 101)).status === 400 && (await aceptar('abc', T.pedro, 2)).status === 400 && (await aceptar(A, T.carlos, 2)).status === 403);
    r = await aceptar(A, T.pedro, 2);
    check('aceptar: 200 con mensaje y el pedido "en_camino" (reutiliza las mismas reglas que /pedidos)', r.status === 200 && r.body.message === 'Pedido aceptado exitosamente' && r.body.pedido.estado === 'en_camino' && r.body.pedido.repartidorId === repPedro && r.body.pedido.total === 7.5);
    check('otro repartidor intenta aceptarlo: 409', (await aceptar(A, T.rosa, 2)).status === 409);
    check('ya no aparece en pendientes', !(await api('GET', '/api/repartidores/pendientes', null, T.pedro)).body.pedidos.some((x) => x.id === A));
    r = await api('GET', '/api/repartidores/mis-pedidos', null, T.pedro);
    check('mis-pedidos: el pedido asignado, ahora SÍ con el teléfono del cliente', r.status === 200 && r.body.pedidos.length === 1 && r.body.pedidos[0].id === A && r.body.pedidos[0].cliente.telefono !== undefined);
    check('otro repartidor no ve pedidos ajenos (mis-pedidos y entregas-activas vacíos)', (await api('GET', '/api/repartidores/mis-pedidos', null, T.rosa)).body.pedidos.length === 0 && (await api('GET', '/api/repartidores/entregas-activas', null, T.rosa)).body.entregas.length === 0);
    r = await api('GET', '/api/repartidores/entregas-activas', null, T.pedro);
    check('entregas-activas (ruta que la app usaba y no existía): { entregas } con el pedido en curso', r.status === 200 && r.body.entregas.length === 1 && r.body.entregas[0].id === A);
    const est2 = (id, estado, token = T.pedro) => api('PUT', `/api/repartidores/pedidos/${id}/estado`, { estado }, token);
    check('estado inválido ("recogido" o "xx") -> 400 · repartidor no asignado -> 404', (await est2(A, 'recogido')).status === 400 && (await est2(A, 'xx')).status === 400 && (await est2(A, 'en_camino', T.rosa)).status === 404);
    r = await est2(A, 'en_camino');
    check('ruta heredada: "en_camino" = lo recogí y voy hacia el cliente -> pedido "recogido"', r.status === 200 && r.body.pedido.estado === 'recogido' && r.body.pedido.fechaRecogida);
    check('repetirlo es inofensivo (200, sigue "recogido")', (await est2(A, 'en_camino')).body.pedido.estado === 'recogido');
    check('entregar: 200 y estado "entregado" · entregarlo otra vez: 409', (await est2(A, 'entregado')).body.pedido.estado === 'entregado' && (await est2(A, 'entregado')).status === 409);
    check('entregado ya no es entrega activa, pero sigue en mis-pedidos', (await api('GET', '/api/repartidores/entregas-activas', null, T.pedro)).body.entregas.length === 0 && (await api('GET', '/api/repartidores/mis-pedidos', null, T.pedro)).body.pedidos.length === 1);

    seccion('4. Ubicación (quién la ve y a quién se avisa)');
    const antes = await hist();
    r = await api('PUT', '/api/repartidores/ubicacion', { latitud: -0.19, longitud: -78.48 }, T.pedro);
    check('actualizar ubicación: 200 y se guarda', r.status === 200 && r.body.ubicacion.latitud === -0.19 && Number((await q('SELECT latitud l FROM trepartidores WHERE cusuario=$1 AND fhasta>now()', [repPedro]))[0].l) === -0.19);
    check('la ubicación es columna volátil: NO genera versiones en HISTREPARTIDORES', (await hist()) === antes);
    check('latitud fuera de rango -> 400 · falta longitud -> 400 · un cliente -> 403', (await api('PUT', '/api/repartidores/ubicacion', { latitud: 200, longitud: 0 }, T.pedro)).status === 400 && (await api('PUT', '/api/repartidores/ubicacion', { latitud: 1 }, T.pedro)).status === 400 && (await api('PUT', '/api/repartidores/ubicacion', { latitud: 1, longitud: 1 }, T.carlos)).status === 403);
    const C = await pedido(true);
    await aceptar(C, T.pedro, 2);
    check('GET /:id/ubicacion: el cliente del pedido en curso la ve (con números)', (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.carlos)).body.lat === -0.19);
    check('...también el vendedor del pedido y el propio repartidor', (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.luis)).status === 200 && (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.pedro)).status === 200);
    check('SEGURIDAD: otro cliente, otro vendedor o un repartidor ajeno NO pueden rastrearlo (404); sin token 401; id inválido 400', (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.maria)).status === 404 && (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.ana)).status === 404 && (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.rosa)).status === 404 && (await api('GET', `/api/repartidores/${repPedro}/ubicacion`)).status === 401 && (await api('GET', '/api/repartidores/A-B/ubicacion', null, T.carlos)).status === 400);
    check('un repartidor sin ubicación guardada: 404 "Ubicación no disponible"', (await api('GET', `/api/repartidores/${repRosa}/ubicacion`, null, T.rosa)).body.code === 'UBICACIONNODISPONIBLE');
    const sCarlos = await conectar(T.carlos); const sMaria = await conectar(T.maria);
    await emitir(sCarlos, 'pedido:join', { pedidoId: C });
    const paraCarlos = esperar(sCarlos, 'pedido:ubicacion', 3000); const paraMaria = esperar(sMaria, 'pedido:ubicacion', 1500);
    await api('PUT', '/api/repartidores/ubicacion', { latitud: -0.2, longitud: -78.5 }, T.pedro);
    const uc = await paraCarlos;
    check('la ubicación por REST se emite a la sala del pedido: el cliente la recibe en vivo', uc && uc.lat === -0.2 && uc.pedidoId === C);
    check('PRIVACIDAD: un cliente ajeno conectado NO recibe la ubicación (antes se emitía a TODOS)', (await paraMaria) === null);
    await est2(C, 'en_camino'); await est2(C, 'entregado');
    check('al terminar la entrega el cliente ya no puede rastrear al repartidor (404)', (await api('GET', `/api/repartidores/${repPedro}/ubicacion`, null, T.carlos)).status === 404);

    seccion('5. Consultas protegidas');
    await q("UPDATE trepartidores SET disponible=false WHERE cusuario=$1 AND fhasta>now()", [repRosa]);
    check('GET /disponibles ya no es público: sin token 401 · cliente 403', (await api('GET', '/api/repartidores/disponibles')).status === 401 && (await api('GET', '/api/repartidores/disponibles', null, T.carlos)).status === 403);
    r = await api('GET', '/api/repartidores/disponibles', null, T.luis);
    check('un vendedor ve solo los disponibles y aprobados, SIN correo ni teléfono', r.status === 200 && r.body.repartidores.length === 1 && r.body.repartidores[0].id === repPedro && r.body.repartidores[0].usuario.email === undefined && r.body.repartidores[0].usuario.telefono === undefined);
    check('GET / (lista completa con datos de contacto) es solo para administradores: vendedor 403 · repartidor 403', (await api('GET', '/api/repartidores', null, T.luis)).status === 403 && (await api('GET', '/api/repartidores', null, T.pedro)).status === 403);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
