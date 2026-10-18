// Prueba de extremo a extremo de las TARIFAS: envío por distancia (base + km de ruta, redondeado a 5 centavos),
// comisión (desde 2026-10-18 es 0: se cobra una suscripción mensual), cotización en el carrito, estimación en la lista
// de negocios y el admin.
// Uso:  npm run test:tarifas   (desde la carpeta backend, con Docker/Postgres en marcha)
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3097, bd: 'vallexpress_test_tarifas' });
const { check, seccion, api } = t;
const LOCAL = { lat: -0.18, lng: -78.48 };
const CASA = { lat: -0.19, lng: -78.49 };

// Lo mismo que calcula el servidor, para comparar
function km(a, b) {
  const rad = (g) => (g * Math.PI) / 180;
  const h = Math.sin(rad(b.lat - a.lat) / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lng - a.lng) / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(h));
}
const envioEsperado = ({ base, porKm, factor }, a, b) => {
  const ruta = Number((km(a, b) * factor).toFixed(2));
  return { ruta, costo: Math.ceil(Math.round((base + porKm * ruta) * 100) / 5) * 5 / 100 };
};

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const admin = await api('POST', '/api/auth/login', { email: 'admin', password: '!' });
    // El admin de la BD temporal no tiene clave: se le pone una por SQL (como el script admin:clave)
    const { hashClave } = require('../src/shared/utils/clave');
    await q("UPDATE tusuarios SET clavehash=$1 WHERE cusuario='admin' AND fhasta='2999-12-31 00:00:00-05'", [await hashClave('admin-secreta-1')]);
    const A = (await api('POST', '/api/auth/login', { email: 'admin', password: 'admin-secreta-1' })).body.token;
    check('el administrador entra', !!A && admin.status === 401);

    seccion('1. Tarifas por defecto');
    let r = await api('GET', '/api/admin/tarifas', null, A);
    const T = r.body.tarifas;
    check('envío $1.00 base + $0.30/km, factor 1.3 y comisión 0 % (ahora hay suscripción)', r.status === 200 && T.envioBase === 1 && T.envioPorKm === 0.3 && T.factorRuta === 1.3 && T.comisionPorcentaje === 0, JSON.stringify(r.body));

    seccion('2. Preparación');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: LOCAL.lat, longitud: LOCAL.lng }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    r = await api('PUT', '/api/mi-negocio', { costoEnvio: 9.99 }, L);
    check('el negocio ya no fija el costo de envío (se ignora)', r.status === 200 && r.body.negocio.costoEnvio !== 9.99);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 12.5 }, L)).body.producto;
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = carlos.token;
    const ana = await t.registrar('ana@test.com', 'Ana', 'Ríos', 'cliente');
    r = await api('GET', '/api/negocios', null, ana.token);
    const sinDir = r.body.negocios.find((n) => n.id === pizza.negocioId);
    check('sin dirección: se muestra la tarifa base ("desde") sin estimar', sinDir?.costoEnvio === 1 && sinDir.envioEstimado === false, JSON.stringify(sinDir));
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: CASA.lat, longitud: CASA.lng, tipo: 'DOM', esPredeterminada: true }, C)).body.direccion;
    const esp = envioEsperado({ base: 1, porKm: 0.3, factor: 1.3 }, LOCAL, CASA);

    seccion('3. Envío estimado y cotización');
    r = await api('GET', '/api/negocios', null, C);
    const conDir = r.body.negocios.find((n) => n.id === pizza.negocioId);
    check(`en la lista: envío estimado a su casa ($${esp.costo}, ${esp.ruta} km de ruta)`, conDir?.costoEnvio === esp.costo && conDir.distanciaKm === esp.ruta && conDir.envioEstimado === true, JSON.stringify(conDir));
    r = await api('GET', `/api/pedidos/cotizar?negocioId=${pizza.negocioId}&direccionId=${dir.id}`, null, C);
    check('cotizar en el carrito: el mismo envío y dentro de cobertura', r.status === 200 && r.body.costoEnvio === esp.costo && r.body.distanciaKm === esp.ruta && r.body.fueraDeCobertura === false, JSON.stringify(r.body));
    check('el envío queda redondeado a 5 centavos', Math.round(r.body.costoEnvio * 100) % 5 === 0);
    r = await api('GET', `/api/pedidos/cotizar?negocioId=${pizza.negocioId}&direccionId=999999`, null, C);
    check('cotizar con una dirección ajena o inexistente: 404', r.status === 404);
    r = await api('GET', `/api/pedidos/cotizar?negocioId=${pizza.negocioId}`, null, C);
    check('cotizar sin dirección: 400', r.status === 400);
    const lejos = (await api('POST', '/api/direcciones', { direccion: 'Muy lejos', latitud: -0.5, longitud: -78.9, tipo: 'TRA' }, C)).body.direccion;
    r = await api('GET', `/api/pedidos/cotizar?negocioId=${pizza.negocioId}&direccionId=${lejos.id}`, null, C);
    check('una dirección a más de 5 km: fuera de cobertura', r.status === 200 && r.body.fueraDeCobertura === true && r.body.radioKm === 5);

    seccion('4. El pedido guarda envío, distancia y comisión');
    const pedir = async () => (await api('POST', '/api/pedidos', { negocioId: pizza.negocioId, direccionId: dir.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 2 }] }, C));
    r = await pedir();
    const p1 = r.body.pedido;
    check(`envío $${esp.costo} y total = 25.00 + envío`, r.status === 201 && p1.costoEnvio === esp.costo && p1.total === Number((25 + esp.costo).toFixed(2)) && p1.distanciaKm === esp.ruta, JSON.stringify(r.body));
    check('el cliente NO ve la comisión', !('comision' in p1) && !('recibeNegocio' in p1));
    const fila = (await q("SELECT comision, comisionporcentaje, distanciakm FROM tpedidos WHERE cpedido=$1 AND fhasta='2999-12-31 00:00:00-05'", [p1.id]))[0];
    check('en la BD: sin comisión y con la distancia', Number(fila.comision) === 0 && Number(fila.comisionporcentaje) === 0 && Number(fila.distanciakm) === esp.ruta, JSON.stringify(fila));
    r = await api('GET', `/api/pedidos/${p1.id}`, null, L);
    check('el negocio recibe todo lo vendido en productos (25.00)', r.body.pedido?.comision === 0 && r.body.pedido.recibeNegocio === 25, JSON.stringify(r.body.pedido));
    r = await api('GET', `/api/admin/pedidos/${p1.id}`, null, A);
    check('el administrador también', r.body.pedido?.comision === 0);

    seccion('5. El admin cambia las tarifas');
    r = await api('PUT', '/api/admin/tarifas', { envioBase: 1.5, envioPorKm: 0.5, comisionPorcentaje: 12 }, A);
    check('nuevas tarifas guardadas; la comisión ya no se cambia (sigue en 0)', r.status === 200 && r.body.tarifas.envioBase === 1.5 && r.body.tarifas.envioPorKm === 0.5 && r.body.tarifas.comisionPorcentaje === 0, JSON.stringify(r.body));
    check('quedan en la auditoría', (await q("SELECT 1 FROM tauditoria WHERE accion='TARIFASCAMBIADAS'")).length === 1);
    r = await api('PUT', '/api/admin/tarifas', { comisionPorcentaje: 10 }, A);
    check('solo la comisión: 400 (no hay nada que cambiar)', r.status === 400);
    r = await api('PUT', '/api/admin/tarifas', {}, A);
    check('sin ningún cambio: 400', r.status === 400);
    r = await api('PUT', '/api/admin/tarifas', { envioBase: 0 }, L);
    check('un vendedor no cambia las tarifas: 403', r.status === 403);
    const esp2 = envioEsperado({ base: 1.5, porKm: 0.5, factor: 1.3 }, LOCAL, CASA);
    r = await pedir();
    const p2 = r.body.pedido;
    check(`el pedido nuevo usa las nuevas: envío $${esp2.costo}`, p2?.costoEnvio === esp2.costo, JSON.stringify(r.body));
    check('y sin comisión', Number((await q("SELECT comision FROM tpedidos WHERE cpedido=$1 AND fhasta='2999-12-31 00:00:00-05'", [p2.id]))[0].comision) === 0);
    r = await api('GET', `/api/pedidos/${p1.id}`, null, L);
    check('el pedido viejo NO cambia (sigue con su envío)', r.body.pedido.costoEnvio === esp.costo);

    seccion('6. Repartidor y resumen');
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, pedro.token);
    for (const e of ['confirmado', 'listo']) await api('PATCH', `/api/mi-negocio/pedidos/${p1.id}/estado`, { estado: e }, L);
    r = await api('GET', '/api/repartidor/pedidos/libres', null, pedro.token);
    const libre = (r.body.listos || []).find((p) => p.id === p1.id);
    check('el repartidor ve lo que gana: el envío completo', libre?.costoEnvio === esp.costo && !('comision' in libre), JSON.stringify(libre));
    for (const paso of ['aceptar', 'recogido', 'entregado']) await api('PATCH', `/api/repartidor/pedidos/${p1.id}/${paso}`, null, pedro.token);
    r = await api('GET', '/api/admin/resumen', null, A);
    check('el resumen de hoy ya no suma comisión por pedido', r.body.hoy?.comisiones === 0 && r.body.hoy.entregados === 1, JSON.stringify(r.body.hoy));

    seccion('7. Zona de servicio');
    r = await api('GET', '/api/negocios/zona', null, C);
    check('la app conoce la zona (en las pruebas, sin límite)', r.status === 200 && r.body.zona.nombre === 'Yantzaza' && r.body.zona.radioKm === 0, JSON.stringify(r.body));
    r = await api('PUT', '/api/admin/zona', { nombre: 'Quito Norte', latitud: LOCAL.lat, longitud: LOCAL.lng, radioKm: 3 }, A);
    check('el admin fija la zona: Quito Norte, 3 km', r.status === 200 && r.body.zona.nombre === 'Quito Norte' && r.body.zona.radioKm === 3, JSON.stringify(r.body));
    r = await api('PUT', '/api/admin/zona', { radioKm: 900 }, A);
    check('radio fuera de rango: 400', r.status === 400);
    r = await api('PUT', '/api/admin/zona', { radioKm: 5 }, L);
    check('un vendedor no cambia la zona: 403', r.status === 403);
    r = await api('POST', '/api/direcciones', { direccion: 'Cerca', latitud: CASA.lat, longitud: CASA.lng, tipo: 'FAM' }, C);
    check('una dirección dentro de la zona se guarda', r.status === 201, JSON.stringify(r.body));
    r = await api('POST', '/api/direcciones', { direccion: 'Cuenca', latitud: -2.9, longitud: -79.0, tipo: 'OTR' }, C);
    check('una dirección fuera de la zona: 409 FUERADEZONA con mensaje amable', r.status === 409 && r.body.code === 'FUERADEZONA' && /Quito Norte/.test(r.body.error) && /todavía no llega/.test(r.body.error), JSON.stringify(r.body));
    r = await api('PUT', `/api/direcciones/${dir.id}`, { latitud: -2.9, longitud: -79.0 }, C);
    check('mover una dirección fuera de la zona: 409', r.status === 409 && r.body.code === 'FUERADEZONA');
    r = await api('PUT', '/api/mi-negocio/local', { direccion: 'Lejos', latitud: -0.5, longitud: -78.9 }, L);
    check('el local del negocio fuera de la zona: 409', r.status === 409 && r.body.code === 'FUERADEZONA' && /tu local/.test(r.body.error));
    r = await api('POST', '/api/pedidos', { negocioId: pizza.negocioId, direccionId: lejos.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 2 }] }, C);
    check('pedir a una dirección guardada que quedó fuera de la zona: 409', r.status === 409 && r.body.code === 'FUERADEZONA');
    r = await api('GET', '/api/negocios/zona', null, C);
    check('la app ve la zona nueva', r.body.zona.nombre === 'Quito Norte' && r.body.zona.radioKm === 3);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
