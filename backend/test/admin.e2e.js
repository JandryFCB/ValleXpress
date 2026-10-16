// Prueba de extremo a extremo del ADMINISTRADOR: clave inicial por script, aprobación de negocios y repartidores,
// métricas, pedidos (ver todos y cancelar una disputa), bloqueo de usuarios y la aprobación automática.
// Uso:  npm run test:admin   (desde la carpeta backend, con Docker/Postgres en marcha)
// Crea su PROPIA base temporal, levanta el servidor contra ella y al terminar borra todo.
const path = require('path');
const { spawnSync } = require('child_process');
const crearArnes = require('./arnes');

const BD = 'vallexpress_test_admin';
const t = crearArnes({ puerto: 3094, bd: BD });
const { check, seccion, api } = t;
const CLAVEADMIN = 'admin-secreta-1';

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());

    seccion('1. Clave inicial del administrador');
    let r = await api('POST', '/api/auth/login', { email: 'admin', password: '!' });
    check('recién creada la BD, nadie puede entrar como admin', r.status === 401);
    const script = spawnSync(process.execPath, ['scripts/clave-admin.js'], { cwd: path.resolve(__dirname, '..'), env: { ...process.env, DB_NAME: BD, CLAVE: CLAVEADMIN }, encoding: 'utf8' });
    check('el script admin:clave le pone la clave', script.status === 0, script.stderr);
    const sinClave = spawnSync(process.execPath, ['scripts/clave-admin.js'], { cwd: path.resolve(__dirname, '..'), env: { ...process.env, DB_NAME: BD, CLAVE: 'corta' }, encoding: 'utf8' });
    check('con una clave de menos de 8 caracteres se niega', sinClave.status === 1);
    r = await api('POST', '/api/auth/login', { email: 'admin', password: CLAVEADMIN });
    const A = r.body?.token;
    check('el administrador entra con su clave', r.status === 200 && r.body.usuario?.tipoUsuario === 'administrador', JSON.stringify(r.body));
    const cliente = await t.registrar('ana@test.com', 'Ana', 'Ríos', 'cliente');
    r = await api('GET', '/api/admin/resumen', null, cliente.token);
    check('un cliente no entra al panel: 403', r.status === 403);
    r = await api('GET', '/api/admin/resumen');
    check('sin sesión: 401', r.status === 401);

    seccion('2. Sin aprobación automática: los nuevos esperan revisión');
    r = await api('PUT', '/api/admin/configuracion', { aprobacionAutomatica: false }, A);
    check('se apaga la aprobación automática', r.status === 200 && r.body.aprobacionAutomatica === false);
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    r = await api('GET', '/api/mi-negocio', null, L);
    const negocioId = r.body.negocio?.id;
    check('el negocio nuevo queda pendiente', r.body.negocio?.aprobacion === 'pendiente', JSON.stringify(r.body));
    r = await api('GET', '/api/negocios', null, cliente.token);
    check('y no aparece en la lista pública', !r.body.negocios.some((n) => n.id === negocioId));
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    const P = pedro.token;
    r = await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    check('el repartidor pendiente no puede ponerse en línea', r.status === 403 && r.body.code === 'REPARTIDORNOAPROBADO');

    seccion('3. Resumen');
    r = await api('GET', '/api/admin/resumen', null, A);
    const res = r.body;
    check('resumen: 2 pendientes de revisión', r.status === 200 && res.pendientes === 2, JSON.stringify(res));
    check('usuarios por rol (incluye al admin)', res.usuarios.cliente === 1 && res.usuarios.vendedor === 1 && res.usuarios.repartidor === 1 && res.usuarios.administrador === 1, JSON.stringify(res.usuarios));
    check('7 días en la gráfica de ventas, hoy sin ventas', res.ultimos7Dias.length === 7 && res.hoy.ventas === 0 && res.aprobacionAutomatica === false);

    seccion('4. Aprobar negocios');
    r = await api('GET', '/api/admin/negocios?aprobacion=pendiente', null, A);
    const pend = r.body.negocios?.[0];
    check('lista de pendientes con los datos del dueño', r.status === 200 && pend?.id === negocioId && pend.dueno?.email === 'luis@test.com' && pend.aprobacion === 'pendiente', JSON.stringify(r.body));
    r = await api('PATCH', `/api/admin/negocios/${negocioId}/aprobacion`, { estado: 'rechazado' }, A);
    check('rechazar sin motivo: 400 MOTIVOREQUERIDO', r.status === 400 && r.body.code === 'MOTIVOREQUERIDO');
    r = await api('POST', '/api/mi-negocio/revision', null, L);
    check('pedir revisión estando pendiente: 409 YAENREVISION', r.status === 409 && r.body.code === 'YAENREVISION');
    r = await api('PATCH', `/api/admin/negocios/${negocioId}/aprobacion`, { estado: 'rechazado', motivo: 'Falta el RUC del local' }, A);
    check('rechazar con motivo: 200', r.status === 200 && r.body.negocio.aprobacion === 'rechazado');
    r = await api('GET', '/api/mi-negocio', null, L);
    check('el dueño ve el rechazo con su motivo y a quién escribir', r.body.negocio?.aprobacion === 'rechazado' && r.body.negocio.motivoAprobacion === 'Falta el RUC del local' && 'soporte' in r.body.negocio, JSON.stringify(r.body.negocio));
    r = await api('GET', `/api/negocios/${negocioId}`, null, cliente.token);
    check('un cliente no ve el negocio rechazado (ni su motivo): 404', r.status === 404);
    r = await api('POST', '/api/mi-negocio/revision', null, L);
    check('corrige y pide una nueva revisión: vuelve a pendiente sin motivo', r.status === 200 && r.body.negocio.aprobacion === 'pendiente' && r.body.negocio.motivoAprobacion === null, JSON.stringify(r.body));
    check('el motivo queda en el historial (versión cerrada)', (await q("SELECT 1 FROM tnegocios WHERE cnegocio=$1 AND motivoaprobacion='Falta el RUC del local' AND fhasta < '2999-01-01'", [negocioId])).length === 1);
    check('y la solicitud queda en la auditoría', (await q("SELECT 1 FROM tauditoria WHERE accion='REVISIONSOLICITADA' AND entidad='NEGOCIOS'")).length === 1);
    const sL = await t.conectar(L);
    const avisoNegocio = t.esperar(sL, 'notificacion');
    r = await api('PATCH', `/api/admin/negocios/${negocioId}/aprobacion`, { estado: 'aprobado' }, A);
    check('aprobar: 200', r.status === 200 && r.body.negocio.aprobacion === 'aprobado' && !!r.body.negocio.aprobadoEn, JSON.stringify(r.body));
    check('el dueño recibe "¡Tu cuenta fue aprobada!" en vivo', (await avisoNegocio)?.tipo === 'negocio_aprobado');
    r = await api('PATCH', `/api/admin/negocios/${negocioId}/aprobacion`, { estado: 'aprobado' }, A);
    check('aprobarlo otra vez: 409 SINCAMBIOS', r.status === 409 && r.body.code === 'SINCAMBIOS');
    await api('PUT', '/api/mi-negocio', { costoEnvio: 1 }, L);
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: -0.18, longitud: -78.48 }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10, controlaStock: true, stock: 5 }, L)).body.producto;
    r = await api('GET', '/api/negocios', null, cliente.token);
    check('aprobado: ya aparece en la lista pública', r.body.negocios.some((n) => n.id === negocioId));

    seccion('5. Aprobar y suspender repartidores');
    r = await api('GET', '/api/admin/repartidores?aprobacion=pendiente', null, A);
    check('repartidor pendiente con vehículo y contacto', r.body.repartidores?.[0]?.usuario === pedro.usuario.id && r.body.repartidores[0].placa === 'ABC1234' && r.body.repartidores[0].contacto?.email === 'pedro@test.com', JSON.stringify(r.body));
    r = await api('PATCH', `/api/admin/repartidores/${pedro.usuario.id}/aprobacion`, { estado: 'aprobado' }, A);
    check('aprobar al repartidor: 200', r.status === 200 && r.body.repartidor.aprobacion === 'aprobado');
    r = await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    check('ya puede ponerse en línea', r.status === 200 && r.body.repartidor.disponible === true);
    r = await api('PATCH', `/api/admin/repartidores/${pedro.usuario.id}/aprobacion`, { estado: 'suspendido', motivo: 'Documentos vencidos' }, A);
    check('suspenderlo con motivo: queda fuera de línea', r.status === 200 && r.body.repartidor.aprobacion === 'suspendido' && r.body.repartidor.disponible === false);
    check('y recibe el aviso con el motivo', (await q("SELECT mensaje FROM tnotificaciones WHERE cusuario=$1 AND tipo='repartidor_suspendido'", [pedro.usuario.id]))[0]?.mensaje.includes('Documentos vencidos'));
    r = await api('GET', '/api/repartidor', null, P);
    check('en su perfil ve la suspensión y el motivo', r.body.repartidor?.aprobacion === 'suspendido' && r.body.repartidor.motivoAprobacion === 'Documentos vencidos', JSON.stringify(r.body));
    r = await api('POST', '/api/repartidor/revision', null, P);
    check('suspendido no puede pedir revisión por su cuenta: 409', r.status === 409 && r.body.code === 'REVISIONNOPERMITIDA');
    r = await api('PATCH', `/api/admin/repartidores/${pedro.usuario.id}/aprobacion`, { estado: 'rechazado', motivo: 'Placa ilegible' }, A);
    r = await api('POST', '/api/repartidor/revision', null, P);
    check('rechazado sí: vuelve a pendiente', r.status === 200 && r.body.repartidor.aprobacion === 'pendiente' && r.body.repartidor.motivoAprobacion === null, JSON.stringify(r.body));
    r = await api('PATCH', `/api/admin/repartidores/${pedro.usuario.id}/aprobacion`, { estado: 'aprobado' }, A);
    r = await api('GET', '/api/repartidor', null, P);
    check('aprobado de nuevo: sin motivo', r.body.repartidor.aprobacion === 'aprobado' && r.body.repartidor.motivoAprobacion === null);
    await api('PATCH', `/api/admin/repartidores/${pedro.usuario.id}/aprobacion`, { estado: 'suspendido', motivo: 'Documentos vencidos' }, A);
    r = await api('PATCH', `/api/admin/repartidores/noexiste/aprobacion`, { estado: 'aprobado' }, A);
    check('repartidor que no existe: 404', r.status === 404);

    seccion('6. Pedidos: verlos todos y cancelar una disputa');
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: -0.185, longitud: -78.485, tipo: 'DOM' }, cliente.token)).body.direccion;
    const pedido = (await api('POST', '/api/pedidos', { negocioId, direccionId: dir.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 2 }] }, cliente.token)).body.pedido;
    await api('PATCH', `/api/mi-negocio/pedidos/${pedido.id}/estado`, { estado: 'confirmado' }, L);
    r = await api('GET', '/api/admin/pedidos?estado=activos', null, A);
    check('el admin ve los pedidos de todos, con el cliente', r.status === 200 && r.body.pedidos[0]?.id === pedido.id && r.body.pedidos[0].cliente?.nombre === 'Ana', JSON.stringify(r.body.pedidos?.[0]?.cliente));
    r = await api('GET', `/api/admin/pedidos/${pedido.id}`, null, A);
    check('y su detalle con la línea de tiempo y el teléfono del negocio', r.status === 200 && r.body.pedido.lineaTiempo.length === 2 && 'telefono' in r.body.pedido.negocio);
    r = await api('GET', '/api/admin/pedidos?estado=volando', null, A);
    check('estado inventado: 400', r.status === 400);
    r = await api('PATCH', `/api/admin/pedidos/${pedido.id}/cancelar`, { motivo: 'no' }, A);
    check('cancelar con motivo muy corto: 400', r.status === 400);
    const sAna = await t.conectar(cliente.token);
    const avisoAna = t.esperar(sAna, 'notificacion');
    r = await api('PATCH', `/api/admin/pedidos/${pedido.id}/cancelar`, { motivo: 'El negocio no responde' }, A);
    check('cancelar la disputa: 200 y el motivo queda en el pedido', r.status === 200 && r.body.pedido.estado === 'cancelado' && r.body.pedido.motivoCancelacion === 'Cancelado por ValleXpress: El negocio no responde', JSON.stringify(r.body));
    check('la clienta recibe el aviso en vivo', (await avisoAna)?.tipo === 'pedido_cancelado');
    check('el negocio también recibe el aviso', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='pedido_cancelado'", [luis.usuario.id])).length === 1);
    check('las 2 pizzas vuelven al stock', (await q('SELECT stock FROM tproductosinventario WHERE cproducto=$1', [pizza.id]))[0]?.stock === 5);
    r = await api('PATCH', `/api/admin/pedidos/${pedido.id}/cancelar`, { motivo: 'Otra vez por si acaso' }, A);
    check('cancelarlo de nuevo: 409', r.status === 409 && r.body.code === 'TRANSICIONINVALIDA');
    r = await api('GET', `/api/admin/pedidos/${pedido.id}`, null, cliente.token);
    check('un cliente no usa la ruta del admin: 403', r.status === 403);

    seccion('7. Bloquear usuarios');
    r = await api('GET', '/api/admin/usuarios?rol=cliente', null, A);
    check('usuarios por rol', r.status === 200 && r.body.usuarios.length === 1 && r.body.usuarios[0].usuario === cliente.usuario.id);
    r = await api('GET', '/api/admin/usuarios?q=mora', null, A);
    check('buscar por apellido', r.body.usuarios.length === 1 && r.body.usuarios[0].usuario === luis.usuario.id);
    r = await api('PATCH', `/api/admin/usuarios/${cliente.usuario.id}/estado`, { activo: false }, A);
    check('bloquear sin motivo: 400', r.status === 400 && r.body.code === 'MOTIVOREQUERIDO');
    const cortado = new Promise((res) => { sAna.once('disconnect', () => res(true)); setTimeout(() => res(false), 3000); });
    r = await api('PATCH', `/api/admin/usuarios/${cliente.usuario.id}/estado`, { activo: false, motivo: 'Pedidos falsos' }, A);
    check('bloquear: 200', r.status === 200 && r.body.usuario.activo === false);
    check('su conexión en vivo se corta al instante', await cortado);
    r = await api('GET', '/api/pedidos/mis-pedidos', null, cliente.token);
    check('su token deja de servir: 403 CUENTADESACTIVADA', r.status === 403 && r.body.code === 'CUENTADESACTIVADA');
    r = await api('POST', '/api/auth/refresh', { refreshToken: cliente.refreshToken });
    check('y no puede renovar la sesión', r.status === 401);
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    check('ni volver a entrar', r.status === 403 && r.body.code === 'CUENTADESACTIVADA');
    check('el login le dice que está bloqueada y a quién escribir', r.body.estatus === 'bloqueado' && /bloqueada/.test(r.body.error) && 'soporte' in r.body, JSON.stringify(r.body));
    r = await api('PATCH', `/api/admin/usuarios/${cliente.usuario.id}/estado`, { activo: true }, A);
    check('desbloquear: 200', r.status === 200 && r.body.usuario.activo === true);
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    check('ya puede entrar de nuevo', r.status === 200);
    r = await api('PATCH', '/api/admin/usuarios/admin/estado', { activo: false, motivo: 'Prueba' }, A);
    check('al administrador no se le bloquea: 403', r.status === 403 && r.body.code === 'ADMINPROTEGIDO');

    seccion('8. Auditoría y aprobación automática');
    const acciones = (await q("SELECT DISTINCT accion FROM tauditoria WHERE cusuario='admin'")).map((f) => f.accion);
    check('todo queda en la auditoría', ['NEGOCIOAPROBACION', 'REPARTIDORAPROBACION', 'PEDIDOCANCELADOADMIN', 'USUARIOBLOQUEADO', 'USUARIOREACTIVADO', 'CONFIGURACIONCAMBIADA'].every((a) => acciones.includes(a)), acciones.join());
    check('el historial de la configuración guarda el valor anterior', (await q("SELECT 1 FROM tconfiguraciones WHERE cconfiguracion='APROBACIONAUTOMATICA'")).length === 2);
    r = await api('PUT', '/api/admin/configuracion', { aprobacionAutomatica: true }, A);
    const rosa = await t.registrar('rosa@test.com', 'Rosa', 'Paz', 'repartidor', { vehiculo: 'Bicicleta' });
    r = await api('GET', '/api/repartidor', null, rosa.token);
    check('con la aprobación automática encendida, el nuevo nace aprobado', r.body.repartidor?.aprobacion === 'aprobado');

    seccion('9. Crear, editar y dar de baja cuentas');
    await api('PUT', '/api/admin/configuracion', { aprobacionAutomatica: false }, A);
    const nuevo = (rol, n, extra = {}) => api('POST', '/api/admin/usuarios', {
      nombre: 'Nuevo', apellido: `Rol${n}`, email: `nuevo${n}@test.com`, cedula: t.cedula(9, 5000 + n), telefono: `098800000${n}`, password: 'secreto1', rol, ...extra,
    }, A);
    r = await nuevo('vendedor', 1);
    check('vendedor sin nombre de negocio: 400', r.status === 400);
    r = await nuevo('vendedor', 1, { nombreNegocio: 'Heladería Nueva', categoriaNegocio: '003' });
    const vend = r.body.usuario;
    check('crear un vendedor con su negocio: 201', r.status === 201 && vend?.rol === 'vendedor' && vend.estatus === 'activo', JSON.stringify(r.body));
    const heladeria = (await q('SELECT cnegocio, cestatusaprobacion FROM tnegocios WHERE cusuario=$1 AND fhasta=$2', [vend.usuario, '2999-12-31 00:00:00-05']))[0];
    check('su negocio nace aprobado aunque la aprobación automática esté apagada', heladeria?.cestatusaprobacion === '002');
    r = await nuevo('repartidor', 2, { vehiculo: 'moto', placa: 'PBC-0456', color: 'Azul' });
    check('crear un repartidor con su moto, ya aprobado', r.status === 201 && (await q('SELECT cestatusaprobacion FROM trepartidores WHERE cusuario=$1', [r.body.usuario.usuario]))[0]?.cestatusaprobacion === '002');
    const repNuevo = r.body.usuario.usuario;
    r = await nuevo('administrador', 3);
    check('crear otro administrador', r.status === 201 && r.body.usuario.rol === 'administrador');
    r = await nuevo('cliente', 3);
    check('correo repetido: 409 EMAILDUPLICADO', r.status === 409 && r.body.code === 'EMAILDUPLICADO');
    r = await api('POST', '/api/auth/login', { email: 'nuevo1@test.com', password: 'secreto1' });
    check('la cuenta creada ya puede entrar', r.status === 200);

    r = await api('PUT', `/api/admin/usuarios/${vend.usuario}`, { nombre: 'Marta', telefono: '0988000099' }, A);
    check('editar nombre y teléfono', r.status === 200 && r.body.usuario.nombre === 'Marta' && r.body.usuario.telefono === '0988000099', JSON.stringify(r.body));
    r = await api('PUT', `/api/admin/usuarios/${vend.usuario}`, { email: 'luis@test.com' }, A);
    check('ponerle el correo de otro: 409', r.status === 409 && r.body.code === 'EMAILDUPLICADO');
    r = await api('PUT', `/api/admin/usuarios/${vend.usuario}/clave`, { clave: 'nueva-clave-9' }, A);
    check('ponerle una clave nueva', r.status === 200);
    r = await api('POST', '/api/auth/login', { email: 'nuevo1@test.com', password: 'nueva-clave-9' });
    check('entra con la clave nueva', r.status === 200);
    r = await api('PUT', `/api/admin/usuarios/${vend.usuario}/foto`, { imagen: await t.imagen(300, 300) }, A);
    check('subirle una foto de perfil', r.status === 200 && /^http/.test(r.body.usuario.foto || ''), JSON.stringify(r.body));
    r = await api('GET', `/api/admin/usuarios/${vend.usuario}`, null, A);
    check('ver la cuenta con su foto', r.status === 200 && !!r.body.usuario.foto);

    r = await api('DELETE', `/api/admin/usuarios/${repNuevo}`, {}, A);
    check('dar de baja sin motivo: 400', r.status === 400);
    r = await api('DELETE', `/api/admin/usuarios/${repNuevo}`, { motivo: 'Ya no trabaja con nosotros' }, A);
    check('dar de baja: la cuenta queda inactiva (no se borra)', r.status === 200 && r.body.usuario.estatus === 'inactivo' && r.body.usuario.activo === false);
    r = await api('POST', '/api/auth/login', { email: 'nuevo2@test.com', password: 'secreto1' });
    check('dada de baja no puede entrar', r.status === 403);
    r = await api('PATCH', `/api/admin/usuarios/${repNuevo}/estado`, { activo: true }, A);
    check('reactivarla', r.status === 200 && r.body.usuario.estatus === 'activo');
    r = await api('DELETE', '/api/admin/usuarios/admin', { motivo: 'Prueba' }, A);
    check('al administrador principal no se le da de baja', r.status === 403 && r.body.code === 'ADMINPROTEGIDO');

    seccion('10. Gestionar un negocio como su dueño');
    const G = `/api/admin/negocios/${negocioId}/gestion`;
    r = await api('GET', G, null, A);
    check('ver el negocio con sus datos privados', r.status === 200 && r.body.negocio.id === negocioId && r.body.negocio.aprobacion === 'aprobado');
    r = await api('PUT', G, { nombre: 'Pizzería Luis Gourmet', costoEnvio: 2.5 }, A);
    check('editar nombre y envío', r.status === 200 && r.body.negocio.nombre === 'Pizzería Luis Gourmet' && r.body.negocio.costoEnvio === 2.5);
    r = await api('PATCH', `${G}/estado`, { abierto: false }, A);
    check('cerrarlo', r.status === 200 && r.body.negocio.abierto === false);
    r = await api('PUT', `${G}/logo`, { imagen: await t.imagen(400, 400) }, A);
    check('cambiar su logo', r.status === 200 && !!r.body.negocio.logo);
    r = await api('POST', `${G}/productos`, { nombre: 'Lasaña', precio: 7.5, seccion: 'Pastas' }, A);
    const lasana = r.body.producto;
    check('crearle un producto', r.status === 201 && lasana?.nombre === 'Lasaña');
    r = await api('PUT', `${G}/productos/${lasana.id}`, { precio: 8 }, A);
    check('editar el precio', r.status === 200 && r.body.producto.precio === 8);
    r = await api('PATCH', `${G}/productos/${lasana.id}/estado`, { estado: 'oculto' }, A);
    check('ocultarlo', r.status === 200 && r.body.producto.estado === 'oculto');
    r = await api('GET', `${G}/productos`, null, A);
    check('lista de productos del negocio', r.status === 200 && r.body.productos.length === 2);
    r = await api('DELETE', `${G}/productos/${lasana.id}`, null, A);
    check('eliminar el producto', r.status === 200 || r.status === 204);
    r = await api('GET', '/api/mi-negocio', null, L);
    check('el dueño ve los cambios del administrador', r.body.negocio.nombre === 'Pizzería Luis Gourmet' && r.body.negocio.abierto === false);
    check('cada cambio queda auditado a nombre del admin', (await q("SELECT COUNT(*)::int AS n FROM tauditoria WHERE cusuario='admin' AND accion='NEGOCIOGESTIONADMIN'"))[0].n >= 6);
    r = await api('GET', '/api/admin/negocios/999999/gestion', null, A);
    check('negocio que no existe: 404', r.status === 404);
    r = await api('PUT', G, { nombre: 'Hackeado' }, L);
    check('un vendedor no usa la ruta del admin: 403', r.status === 403);

    r = await api('PUT', `/api/admin/repartidores/${pedro.usuario.id}`, { vehiculo: 'auto', placa: 'PCD-1234', color: 'Gris' }, A);
    check('editar el vehículo de un repartidor', r.status === 200 && r.body.repartidor.vehiculo === 'auto' && r.body.repartidor.placa === 'PCD1234', JSON.stringify(r.body));
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
