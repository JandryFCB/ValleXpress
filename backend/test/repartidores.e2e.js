// Prueba de extremo a extremo de los REPARTIDORES: registro con vehículo, perfil, en línea, pedidos libres, aceptar
// (dos a la vez), ubicación en vivo por socket, recoger, entregar, calificar y su historial.
// Uso:  npm run test:repartidores   (desde la carpeta backend, con Docker/Postgres en marcha)
// Crea su PROPIA base temporal, levanta el servidor contra ella y al terminar borra todo.
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3095, bd: 'vallexpress_test_repartidores' });
const { check, seccion, api } = t;
const LOCAL = { lat: -0.18, lng: -78.48 };

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());

    seccion('1. Preparación: negocio, producto y clientes');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio', { costoEnvio: 2 }, L);
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: LOCAL.lat, longitud: LOCAL.lng }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10 }, L)).body.producto;
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const C = carlos.token;
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, C)).body.direccion;
    const maria = await t.registrar('maria@test.com', 'María', 'León', 'cliente');
    const pedir = async (token = C, direccionId = dir.id) => (await api('POST', '/api/pedidos', { negocioId: pizza.negocioId, direccionId, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 1 }] }, token)).body.pedido;
    const estadoNegocio = (id, estado) => api('PATCH', `/api/mi-negocio/pedidos/${id}/estado`, { estado }, L);
    check('negocio abierto con local, producto y dos clientes', !!pizza?.id && !!dir?.id && !!maria.token);

    seccion('2. Registro y perfil del repartidor');
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'abc-1234' });
    const P = pedro.token;
    let r = await api('GET', '/api/repartidor', null, P);
    check('se registra con su perfil: moto, placa normalizada, aprobado y fuera de línea', r.status === 200 && r.body.repartidor.vehiculo === 'moto' && r.body.repartidor.placa === 'ABC1234' && r.body.repartidor.aprobacion === 'aprobado' && r.body.repartidor.disponible === false, JSON.stringify(r.body));
    check('en la BD: TREPARTIDORES y su fila de estado', (await q('SELECT 1 FROM trepartidores r JOIN trepartidoresestado e USING (cusuario) WHERE r.cusuario=$1', [pedro.usuario.id])).length === 1);
    const rosa = await t.registrar('rosa@test.com', 'Rosa', 'Paz', 'repartidor', { vehiculo: 'Bicicleta' });
    const R = rosa.token;
    r = await api('GET', '/api/repartidor', null, R);
    check('en bicicleta no se pide placa', r.status === 200 && r.body.repartidor.vehiculo === 'bicicleta' && r.body.repartidor.placa === null);
    const dup = await t.registrar('dup@test.com', 'Dup', 'Dup', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    check('placa de otro repartidor: el registro no se hace', !dup.token && (await q("SELECT 1 FROM tpersonas WHERE correo='dup@test.com'")).length === 0);
    const sin = await t.registrar('sin@test.com', 'Sin', 'Perfil', 'repartidor');
    r = await api('GET', '/api/repartidor', null, sin.token);
    check('registrado sin vehículo: aún no tiene perfil (404)', r.status === 404 && r.body.code === 'REPARTIDORNOENCONTRADO');
    r = await api('POST', '/api/repartidor', { vehiculo: 'auto', placa: 'PBX-0123' }, sin.token);
    check('lo crea después: 201', r.status === 201 && r.body.repartidor.placa === 'PBX0123');
    r = await api('POST', '/api/repartidor', { vehiculo: 'moto', placa: 'PBX0123' }, sin.token);
    check('crearlo otra vez: 409', r.status === 409);
    r = await api('PUT', '/api/repartidor', { vehiculo: 'auto', placa: 'XX' }, P);
    check('placa inválida: 400', r.status === 400 && r.body.code === 'PLACAINVALIDA');
    r = await api('PUT', '/api/repartidor', { vehiculo: 'avion' }, P);
    check('vehículo que no existe: 400', r.status === 400);
    r = await api('PUT', '/api/repartidor', { color: 'Roja' }, P);
    check('cambiar el color: 200 y queda en el historial', r.status === 200 && r.body.repartidor.color === 'Roja' && (await q('SELECT 1 FROM trepartidores WHERE cusuario=$1', [pedro.usuario.id])).length === 2);
    r = await api('GET', '/api/repartidor', null, C);
    check('un cliente no entra a /api/repartidor: 403', r.status === 403);

    seccion('3. Pedidos libres');
    const p1 = await pedir();
    r = await api('GET', '/api/repartidor/pedidos/libres', null, P);
    check('pendiente (sin confirmar): no aparece', r.status === 200 && r.body.listos.length === 0 && r.body.proximos.length === 0);
    await estadoNegocio(p1.id, 'confirmado');
    r = await api('GET', '/api/repartidor/pedidos/libres', null, P);
    const prox = r.body.proximos[0];
    check('confirmado: aparece en "próximos", sin datos del cliente', prox?.id === p1.id && prox.cliente === undefined && prox.entrega.direccion === 'Calle 1' && prox.costoEnvio === 2 && prox.distanciaKm > 0, JSON.stringify(prox));
    r = await api('GET', `/api/pedidos/${p1.id}`, null, P);
    check('el repartidor puede ver el pedido libre, sin el cliente ni el teléfono del negocio', r.status === 200 && r.body.pedido.cliente === undefined && r.body.pedido.negocio.telefono === undefined);
    r = await api('PATCH', `/api/repartidor/pedidos/${p1.id}/aceptar`, null, P);
    check('aceptar fuera de línea: 409 REPARTIDORDESCONECTADO', r.status === 409 && r.body.code === 'REPARTIDORDESCONECTADO');
    r = await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    check('ponerse en línea: 200', r.status === 200 && r.body.repartidor.disponible === true);
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, R);
    r = await api('PATCH', `/api/repartidor/pedidos/${p1.id}/aceptar`, null, P);
    check('aceptar antes de que esté listo: 409 PEDIDONOLISTO', r.status === 409 && r.body.code === 'PEDIDONOLISTO');

    const sP = await t.conectar(P);
    const sR = await t.conectar(R);
    const avisoListo = t.esperar(sP, 'notificacion');
    await api('PUT', '/api/repartidor/ubicacion', { latitud: -0.17, longitud: -78.47 }, P);
    await estadoNegocio(p1.id, 'listo');
    const a1 = await avisoListo;
    check('al quedar listo, los repartidores en línea reciben el aviso con lo que ganan', a1?.tipo === 'pedido_disponible' && a1.pedidoId === p1.id && /\$2\.00/.test(a1.mensaje), JSON.stringify(a1));
    r = await api('GET', '/api/repartidor/pedidos/libres', null, P);
    check('listo: aparece en "listos" con la distancia al negocio', r.body.listos[0]?.id === p1.id && r.body.listos[0].distanciaAlNegocioKm > 0 && r.body.enLinea === true, JSON.stringify(r.body.listos[0]));

    seccion('4. Aceptar (dos repartidores a la vez)');
    const sCarlos = await t.conectar(C);
    const sLuis = await t.conectar(L);
    const avisoCliente = t.esperar(sCarlos, 'notificacion');
    const [ap, ar] = await Promise.all([api('PATCH', `/api/repartidor/pedidos/${p1.id}/aceptar`, null, P), api('PATCH', `/api/repartidor/pedidos/${p1.id}/aceptar`, null, R)]);
    const ganador = ap.status === 200 ? { token: P, usuario: pedro.usuario, socket: sP, nombre: 'Pedro' } : { token: R, usuario: rosa.usuario, socket: sR, nombre: 'Rosa' };
    const perdedor = ap.status === 200 ? { token: R, socket: sR } : { token: P, socket: sP };
    check('solo uno lo gana; el otro recibe 409 PEDIDOASIGNADO', [ap.status, ar.status].sort().join() === '200,409' && [ap.body.code, ar.body.code].includes('PEDIDOASIGNADO'), `${ap.status} ${ar.status}`);
    const ganado = (ap.status === 200 ? ap : ar).body.pedido;
    check('el ganador lo ve "en camino" con los datos del cliente y el teléfono del negocio', ganado.estado === 'en_camino' && ganado.cliente?.nombre === 'Carlos' && !!ganado.negocio.telefono);
    const ac = await avisoCliente;
    check('el cliente recibe "repartidor asignado" con su nombre', ac?.tipo === 'pedido_en_camino' && ac.mensaje.includes(ganador.nombre), JSON.stringify(ac));
    check('el negocio recibe "repartidor en camino"', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='repartidor_asignado'", [luis.usuario.id])).length === 1);
    r = await api('GET', `/api/pedidos/${p1.id}`, null, perdedor.token);
    check('el perdedor ya no puede ver el pedido: 404', r.status === 404);
    const p2 = await pedir();
    await estadoNegocio(p2.id, 'confirmado');
    await estadoNegocio(p2.id, 'listo');
    r = await api('PATCH', `/api/repartidor/pedidos/${p2.id}/aceptar`, null, ganador.token);
    check('con una entrega en curso no puede aceptar otra: 409 ENTREGAENCURSO', r.status === 409 && r.body.code === 'ENTREGAENCURSO');

    seccion('5. Ubicación en vivo');
    const sMaria = await t.conectar(maria.token);
    const llegaCliente = t.esperar(sCarlos, 'pedido:ubicacion');
    const llegaNegocio = t.esperar(sLuis, 'pedido:ubicacion');
    const llegaMaria = t.esperar(sMaria, 'pedido:ubicacion', 800);
    let ack = await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: -0.185, lng: -78.485, velocidad: 5, rumbo: 90 });
    check('el repartidor envía su ubicación: ack con 1 entrega en curso', ack?.ok === true && ack.entregas === 1, JSON.stringify(ack));
    const u1 = await llegaCliente;
    check('el cliente la recibe con su pedido y la velocidad en km/h', u1?.pedidoId === p1.id && u1.latitud === -0.185 && u1.velocidadKmh === 18, JSON.stringify(u1));
    check('el negocio también la recibe', (await llegaNegocio)?.pedidoId === p1.id);
    check('otra clienta NO la recibe', (await llegaMaria) === null);
    ack = await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: -0.186, lng: -78.486 });
    check('más de una vez cada 2 s: MUYFRECUENTE', ack?.error === 'MUYFRECUENTE');
    ack = await t.emitir(sCarlos, 'repartidor:ubicacion', { lat: -0.186, lng: -78.486 });
    check('un cliente no puede enviar ubicaciones: SOLOREPARTIDOR', ack?.error === 'SOLOREPARTIDOR');
    await t.dormir(2100);
    ack = await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: 200, lng: 0 });
    check('coordenadas imposibles: UBICACIONINVALIDA', ack?.error === 'UBICACIONINVALIDA');
    check('se guardó un punto del recorrido', (await q('SELECT 1 FROM trepartidorubicaciones WHERE cpedido=$1', [p1.id])).length === 1);
    r = await api('GET', `/api/pedidos/${p1.id}`, null, C);
    const rep = r.body.pedido.repartidor;
    check('el cliente ve al repartidor con su vehículo y su última ubicación', rep?.nombre === ganador.nombre && !!rep.vehiculo && rep.ubicacion?.latitud === -0.185, JSON.stringify(rep));

    seccion('6. Recoger y entregar');
    r = await api('PATCH', `/api/repartidor/pedidos/${p1.id}/recogido`, null, perdedor.token);
    check('otro repartidor no puede recogerlo: 404', r.status === 404);
    r = await api('PATCH', `/api/repartidor/pedidos/${p1.id}/entregado`, null, ganador.token);
    check('entregar sin haberlo recogido: 409', r.status === 409 && r.body.code === 'TRANSICIONINVALIDA');
    const avisoRecogido = t.esperar(sCarlos, 'notificacion');
    r = await api('PATCH', `/api/repartidor/pedidos/${p1.id}/recogido`, null, ganador.token);
    check('recogido: 200', r.status === 200 && r.body.pedido.estado === 'recogido');
    check('el cliente recibe "tu pedido va hacia ti"', (await avisoRecogido)?.tipo === 'pedido_recogido');

    // Geocerca: la entrega es (-0.19, -78.49)
    const cercas = () => q("SELECT 1 FROM tnotificaciones WHERE cpedido=$1 AND tipo='repartidor_cerca'", [p1.id]);
    await t.dormir(2100);
    let avisoCerca = t.esperar(sCarlos, 'notificacion', 800);
    await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: -0.181, lng: -78.49 });   // ~1 km
    check('a 1 km de la entrega: todavía no avisa que está cerca', (await avisoCerca) === null && (await cercas()).length === 0);
    await t.dormir(2100);
    avisoCerca = t.esperar(sCarlos, 'notificacion');
    await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: -0.1905, lng: -78.49 });  // ~55 m
    const ac2 = await avisoCerca;
    check('a menos de 150 m: el cliente recibe "¡Tu repartidor está cerca!"', ac2?.tipo === 'repartidor_cerca' && ac2.pedidoId === p1.id, JSON.stringify(ac2));
    await t.dormir(2100);
    await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: -0.1902, lng: -78.49 });
    await t.dormir(300);
    check('sigue cerca: el aviso no se repite', (await cercas()).length === 1);

    r = await api('PATCH', `/api/repartidor/pedidos/${p1.id}/entregado`, null, ganador.token);
    check('entregado: 200', r.status === 200 && r.body.pedido.estado === 'entregado');
    r = await api('GET', `/api/pedidos/${p1.id}`, null, C);
    check('entregado: el cliente ya no ve la ubicación del repartidor', r.body.pedido.estado === 'entregado' && r.body.pedido.repartidor.ubicacion === null);
    check('línea de tiempo completa hasta entregado', r.body.pedido.lineaTiempo.map((x) => x.estado).join() === 'pendiente,confirmado,listo,en_camino,recogido,entregado', JSON.stringify(r.body.pedido.lineaTiempo));
    await t.dormir(2100);
    ack = await t.emitir(ganador.socket, 'repartidor:ubicacion', { lat: -0.19, lng: -78.49 });
    check('con la entrega terminada, su ubicación ya no se reenvía a nadie', ack?.ok === true && ack.entregas === 0);

    seccion('7. Recibir, calificar e historial');
    r = await api('PATCH', `/api/pedidos/${p1.id}/recibido`, null, C);
    check('el cliente confirma que lo recibió', r.status === 200 && r.body.pedido.estado === 'recibido');
    r = await api('POST', `/api/pedidos/${p1.id}/calificar`, { puntuacion: 5, destino: 'repartidor', comentario: 'Rapidísimo' }, C);
    check('califica al repartidor: 200', r.status === 200 && r.body.pedido.calificacionRepartidor?.puntuacion === 5);
    r = await api('GET', '/api/repartidor', null, ganador.token);
    check('el repartidor queda con 5.0 y 1 entrega', r.body.repartidor.calificacion === 5 && r.body.repartidor.numeroCalificaciones === 1 && r.body.repartidor.numeroEntregas === 1, JSON.stringify(r.body.repartidor));
    check('y recibe el aviso de pedido completado', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='pedido_recibido'", [ganador.usuario.id])).length === 1);
    r = await api('GET', '/api/repartidor/pedidos?estado=historial', null, ganador.token);
    check('su historial: 1 entrega', r.status === 200 && r.body.pedidos.length === 1 && r.body.pedidos[0].id === p1.id);
    r = await api('GET', '/api/repartidor/pedidos?estado=activos', null, ganador.token);
    check('sin entregas activas', r.body.pedidos.length === 0);
    r = await api('PATCH', `/api/repartidor/pedidos/${p2.id}/aceptar`, null, ganador.token);
    check('ya libre, puede aceptar el siguiente', r.status === 200 && r.body.pedido.estado === 'en_camino');
    r = await api('PATCH', '/api/repartidor/disponibilidad', { disponible: false }, ganador.token);
    check('desconectarse: 200', r.status === 200 && r.body.repartidor.disponible === false);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
