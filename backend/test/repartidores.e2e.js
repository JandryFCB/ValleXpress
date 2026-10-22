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
    // Envío plano de $2 (sin valor por km): esta prueba no es de tarifas (eso lo cubre tarifas.e2e.js)
    await q("UPDATE tconfiguraciones SET valor = CASE cconfiguracion WHEN 'ENVIOBASE' THEN '2'::jsonb ELSE '0'::jsonb END WHERE cconfiguracion IN ('ENVIOBASE','ENVIOPORKM') AND fhasta = '2999-12-31 00:00:00-05'");

    seccion('1. Preparación: negocio, producto y clientes');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
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

    seccion('Vehículo y placa al registrarse');
    const bici = await t.registrar('bici@test.com', 'Bea', 'Ruiz', 'repartidor', { vehiculo: 'bicicleta', placa: 'ABC1234' });
    r = await api('GET', '/api/repartidor', null, bici.token);
    check('en bicicleta la placa se ignora aunque venga', r.status === 200 && r.body.repartidor?.vehiculo === 'bicicleta' && !r.body.repartidor.placa, JSON.stringify(r.body));
    const auto = await t.registrar('auto@test.com', 'Ana', 'Vela', 'repartidor', { vehiculo: 'auto', placa: 'PBC-1234' });
    r = await api('GET', '/api/repartidor', null, auto.token);
    check('placa de auto actual (ABC-1234) se acepta y se guarda sin guion', r.body.repartidor?.placa === 'PBC1234', JSON.stringify(r.body));
    const moto = await t.registrar('moto@test.com', 'Mía', 'Paz', 'repartidor', { vehiculo: 'moto', placa: 'IB-123C' });
    r = await api('GET', '/api/repartidor', null, moto.token);
    check('placa de moto (AB-123C) se acepta', r.body.repartidor?.placa === 'IB123C', JSON.stringify(r.body));
    const otro = await t.registrar('otro@test.com', 'Oto', 'Lima', 'repartidor', { vehiculo: 'Otro', placa: 'ABC1234' });
    check('un vehículo que no existe ("Otro") no se registra', !otro.token);

    seccion('Documentos del repartidor');
    const { hashClave } = require('../src/shared/utils/clave');
    await q("UPDATE tusuarios SET clavehash=$1 WHERE cusuario='admin' AND fhasta='2999-12-31 00:00:00-05'", [await hashClave('admin-secreta-1')]);
    const A = (await api('POST', '/api/auth/login', { email: 'admin', password: 'admin-secreta-1' })).body.token;
    r = await api('GET', '/api/repartidor/documentos', null, bici.token);
    check('en bicicleta pide 3 documentos (cédula frente, reverso y selfie), ninguno subido', r.status === 200 && r.body.documentos.length === 3 && r.body.faltan === 3 && !r.body.completos, JSON.stringify(r.body));
    r = await api('GET', '/api/repartidor/documentos', null, moto.token);
    check('en moto pide además licencia y matrícula (5)', r.body.documentos.length === 5 && r.body.documentos.some((d) => d.tipo === 'licencia') && r.body.documentos.some((d) => d.tipo === 'matricula'));
    const foto = await t.imagen(800, 500, 'jpeg');
    r = await api('PUT', '/api/repartidor/documentos/licencia', { imagen: foto }, bici.token);
    check('licencia en bicicleta: 400 (no se pide)', r.status === 400 && r.body.code === 'DOCUMENTONOREQUERIDO');
    r = await api('PUT', '/api/repartidor/documentos/pasaporte', { imagen: foto }, bici.token);
    check('un documento que no existe: 400', r.status === 400);
    r = await api('PUT', '/api/repartidor/documentos/cedula_frente', {}, bici.token);
    check('sin la foto: 400', r.status === 400);
    r = await api('PUT', '/api/repartidor/documentos/cedula_frente', { imagen: foto }, bici.token);
    const frente = r.body.documentos?.find((d) => d.tipo === 'cedula_frente');
    check('sube la cédula (frente): queda con su foto y faltan 2', r.status === 200 && frente?.subido && /^http/.test(frente.url || '') && r.body.faltan === 2, JSON.stringify(r.body));
    r = await api('PUT', '/api/repartidor/documentos/cedula_frente', { imagen: await t.imagen(820, 510, 'jpeg') }, bici.token);
    check('subir otra del mismo tipo la reemplaza (no se duplica)', r.body.faltan === 2 && (await q("SELECT count(*)::int AS n FROM trepartidordocumentos WHERE cusuario = $1", [bici.usuario.id]))[0].n === 1);
    r = await api('GET', '/api/repartidor/documentos', null, C);
    check('un cliente no tiene documentos de repartidor: 403', r.status === 403);
    await api('PUT', '/api/repartidor/documentos/cedula_reverso', { imagen: foto }, bici.token);
    r = await api('PUT', '/api/repartidor/documentos/selfie', { imagen: foto }, bici.token);
    check('con los 3 subidos quedan completos', r.body.completos === true && r.body.faltan === 0);
    r = await api('GET', `/api/admin/repartidores/${bici.usuario.id}/documentos`, null, A);
    check('el admin ve los documentos del repartidor con sus fotos', r.status === 200 && r.body.completos && r.body.documentos.every((d) => d.url));
    r = await api('GET', `/api/admin/repartidores?q=${bici.usuario.id}`, null, A);
    const enLista = r.body.repartidores?.find((x) => x.usuario === bici.usuario.id || x.usuarioId === bici.usuario.id || x.id === bici.usuario.id);
    check('en la lista de aprobaciones se ve cuántos documentos subió', !!enLista?.documentos && enLista.documentos.subidos === 3 && enLista.documentos.requeridos === 3, JSON.stringify(r.body.repartidores?.[0]));
    check('...y ninguno le falta', Array.isArray(enLista?.documentos?.faltan) && enLista.documentos.faltan.length === 0);
    const incompleto = r.body.repartidores.find((x) => x.documentos && x.documentos.subidos < x.documentos.requeridos);
    check('a quien le faltan documentos se le ven sus nombres (para el aviso al aprobarlo igual)', !incompleto || (incompleto.documentos.faltan.length === incompleto.documentos.requeridos - incompleto.documentos.subidos && incompleto.documentos.faltan.includes('Licencia de conducir')), JSON.stringify(incompleto?.documentos));
    r = await api('GET', `/api/admin/repartidores/${bici.usuario.id}/documentos`, null, bici.token);
    check('un repartidor no ve la ruta del admin: 403', r.status === 403);
    r = await api('GET', '/api/repartidor/documentos', null, bici.token);
    check('los documentos traen el estado de la cuenta (para "En revisión" / "Verificados")', ['aprobado', 'pendiente'].includes(r.body.aprobacion), JSON.stringify(r.body.aprobacion));

    seccion('El tipo de vehículo solo lo cambia el administrador');
    r = await api('PUT', '/api/repartidor', { vehiculo: 'auto', placa: 'PBC-4321' }, moto.token);
    check('el repartidor no cambia su tipo de vehículo: 403', r.status === 403 && r.body.code === 'VEHICULOSOLOADMIN', JSON.stringify(r.body));
    r = await api('PUT', '/api/repartidor', { placa: 'IB-999C' }, moto.token);
    check('ya aprobado, tampoco la placa: 403', r.status === 403 && r.body.code === 'PLACASOLOADMIN', JSON.stringify(r.body));
    r = await api('PUT', '/api/repartidor', { color: 'Negro' }, moto.token);
    check('el color sí lo puede cambiar', r.status === 200 && r.body.repartidor?.color === 'Negro', JSON.stringify(r.body));
    r = await api('PUT', `/api/admin/repartidores/${moto.usuario.id}`, { vehiculo: 'auto', placa: 'PBC-4321', color: 'Gris' }, A);
    check('el administrador sí le cambia el vehículo (moto -> auto)', r.status === 200 && r.body.repartidor?.vehiculo === 'auto' && r.body.repartidor.placa === 'PBC4321', JSON.stringify(r.body));

    seccion('Plazo para subir los documentos');
    process.env.DB_NAME = 'vallexpress_test_repartidores';      // el servicio corre aquí mismo contra la BD de la prueba
    const Docs = require('../src/modules/repartidores/documentos.service');
    await t.registrar('tardio@test.com', 'Tito', 'Tardio', 'repartidor', { vehiculo: 'Moto', placa: 'TTT1234' });
    const tardio = (await q("SELECT usuario FROM vusuarios WHERE email = 'tardio@test.com'"))[0].usuario;
    await q("UPDATE trepartidores SET cestatusaprobacion = '001' WHERE cusuario = $1 AND fhasta = '2999-12-31 00:00:00-05'", [tardio]);
    const dentro = (dias) => new Date(Date.now() + dias * 86400000 + 0);
    const avisos = async () => (await q("SELECT titulo FROM tnotificaciones WHERE cusuario = $1 AND tipo = 'documentos_recordatorio' ORDER BY fcreacion", [tardio])).map((x) => x.titulo);
    const mediodia = (dias) => { const d = dentro(dias); d.setUTCHours(17, 0, 0, 0); return d; };   // 12:00 en Ecuador
    await Docs.vigilarDocumentos({ ahora: mediodia(0.2) });
    check('recién registrado: todavía no se le avisa', (await avisos()).length === 0);
    await Docs.vigilarDocumentos({ ahora: mediodia(1.2) });
    check('al día siguiente: "Sube tus documentos para empezar"', (await avisos())[0]?.startsWith('Sube tus documentos'));
    await Docs.vigilarDocumentos({ ahora: mediodia(1.5) });
    check('no se repite', (await avisos()).length === 1);
    await Docs.vigilarDocumentos({ ahora: mediodia(3.2) });
    check('al tercer día: "Te quedan N días"', (await avisos())[1]?.startsWith('Te quedan'));
    await Docs.vigilarDocumentos({ ahora: mediodia(7.2) });
    const r7 = (await q("SELECT cestatusaprobacion, motivoaprobacion FROM trepartidores WHERE cusuario = $1 AND fhasta = '2999-12-31 00:00:00-05'", [tardio]))[0];
    check('a los 7 días sin documentos: la solicitud se cierra (rechazada, con el motivo)', r7.cestatusaprobacion === '003' && r7.motivoaprobacion.includes('documentos'), JSON.stringify(r7));
    check('y se le avisa', (await avisos()).at(-1) === 'Cerramos tu solicitud de repartidor');
    const completo = await t.registrar('completo@test.com', 'Carla', 'Completa', 'repartidor', { vehiculo: 'bicicleta' });
    await q("UPDATE trepartidores SET cestatusaprobacion = '001' WHERE cusuario = $1 AND fhasta = '2999-12-31 00:00:00-05'", [completo.usuario.id]);
    for (const tipo of ['cedula_frente', 'cedula_reverso', 'selfie']) await api('PUT', `/api/repartidor/documentos/${tipo}`, { imagen: await t.imagen(500, 300, 'jpeg') }, completo.token);
    await Docs.vigilarDocumentos({ ahora: mediodia(9) });
    check('a quien ya subió todos sus documentos no se le cierra (espera la revisión del admin)', (await q("SELECT cestatusaprobacion FROM trepartidores WHERE cusuario = $1 AND fhasta = '2999-12-31 00:00:00-05'", [completo.usuario.id]))[0].cestatusaprobacion === '001');
    check('su cuenta sigue activa (no se bloquea ni se elimina)', (await q("SELECT cestatususuario FROM tusuarios WHERE cusuario = $1 AND fhasta = '2999-12-31 00:00:00-05'", [tardio]))[0].cestatususuario === '001');
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
