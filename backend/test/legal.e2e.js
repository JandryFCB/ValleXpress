// Prueba de extremo a extremo de los DOCUMENTOS LEGALES y la ELIMINACIÓN DE CUENTA:
// textos con los valores vigentes, páginas web públicas, aceptación al registrarse, versión nueva que hay que
// volver a aceptar, y eliminar la cuenta borrando los datos personales también del historial.
// Uso:  npm run test:legal   (desde la carpeta backend, con Docker/Postgres en marcha)
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3099, bd: 'vallexpress_test_legal', env: { REPLY_TO_EMAIL: 'soporte@prueba.ec' } });
const { check, seccion, api, BASE } = t;
const VIGENTE = "'2999-12-31 00:00:00-05'";

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const { hashClave } = require('../src/shared/utils/clave');
    await q(`UPDATE tusuarios SET clavehash=$1 WHERE cusuario='admin' AND fhasta=${VIGENTE}`, [await hashClave('admin-secreta-1')]);
    const A = (await api('POST', '/api/auth/login', { email: 'admin', password: 'admin-secreta-1' })).body.token;
    const versionDe = (id) => require('../src/modules/legal/legal.service').versionDe(id);

    seccion('1. Documentos públicos');
    let r = await api('GET', '/api/legal');
    check('lista los 4 documentos con versión y vigencia', r.status === 200 && r.body.documentos.length === 4 && r.body.documentos.every((d) => d.version && d.vigencia && d.titulo), JSON.stringify(r.body));
    r = await api('GET', '/api/legal/terminos-vendedor');
    const textoVendedor = JSON.stringify(r.body.documento?.bloques || []);
    check('el documento llega en bloques (títulos, párrafos y listas)', r.status === 200 && ['titulo', 'parrafo', 'lista'].every((tipo) => r.body.documento.bloques.some((b) => b.tipo === tipo)));
    check('con los valores vigentes: suscripción $10.00, hasta el día 5 y correo de soporte', textoVendedor.includes('$10.00') && textoVendedor.includes('día 5') && textoVendedor.includes('noviembre de 2026') && textoVendedor.includes('soporte@prueba.ec') && !textoVendedor.includes('comisión del'));
    check('no quedan marcas {{...}} sin completar', !textoVendedor.includes('{{'));
    check('nombra al responsable con su cédula', textoVendedor.includes('Jandry Franklin Cayapa Baque') && textoVendedor.includes('1900830447'));
    r = await api('GET', '/api/legal/nada');
    check('un documento que no existe: 400', r.status === 400);
    for (const id of ['terminos-cliente', 'terminos-repartidor', 'privacidad']) {
      r = await api('GET', `/api/legal/${id}`);
      check(`${id}: completo y sin marcas`, r.status === 200 && r.body.documento.bloques.length > 10 && !JSON.stringify(r.body.documento).includes('{{'));
    }

    seccion('2. Páginas web (Google Play)');
    let w = await fetch(`${BASE}/legal/privacidad`);
    let html = await w.text();
    check('/legal/privacidad es una página HTML pública', w.status === 200 && /text\/html/.test(w.headers.get('content-type')) && html.includes('<h1>Política de privacidad</h1>') && html.includes('<h2>'));
    check('la negrita se convierte y el texto se escapa', html.includes('<strong>Jandry Franklin Cayapa Baque</strong>') && !html.includes('**'));
    w = await fetch(`${BASE}/legal/eliminar-cuenta`);
    html = await w.text();
    check('/legal/eliminar-cuenta explica cómo y qué se borra', w.status === 200 && html.includes('Eliminar mi cuenta') && html.includes('soporte@prueba.ec') && html.includes('Qué datos borramos'));
    w = await fetch(`${BASE}/legal`);
    html = await w.text();
    check('/legal es el índice con los 4 documentos y eliminar cuenta', w.status === 200 && (html.match(/href="\/legal\//g) || []).length >= 5);
    w = await fetch(`${BASE}/legal/no-existe`);
    check('una página legal que no existe: 404', w.status === 404);

    seccion('3. Aceptación al registrarse');
    await api('POST', '/api/auth/send-verification', { email: 'sin@test.com', nombre: 'Sin' });
    await api('POST', '/api/auth/verify-email', { email: 'sin@test.com', code: await t.codigoDe('sin@test.com') });
    r = await api('POST', '/api/auth/register', { nombre: 'Sin', apellido: 'Acepta', email: 'sin@test.com', telefono: '0993111111', cedula: t.cedula(17, 9001), password: 'secreto1', tipoUsuario: 'cliente' });
    check('sin aceptar los términos no hay registro: 400', r.status === 400 && /términos/.test(JSON.stringify(r.body)), JSON.stringify(r.body));
    const ana = await t.registrar('ana@test.com', 'Ana', 'Paz', 'cliente');
    let filas = await q("SELECT documento, version, ip FROM taceptacioneslegales WHERE cusuario = $1 ORDER BY documento", [ana.usuario.id]);
    check('al registrarse quedan aceptados los términos de cliente y la privacidad, con su versión e IP', filas.length === 2 && filas[0].documento === 'privacidad' && filas[1].documento === 'terminos-cliente' && filas[1].version === versionDe('terminos-cliente') && !!filas[0].ip, JSON.stringify(filas));
    r = await api('GET', '/api/legal/pendientes', null, ana.token);
    check('no tiene nada pendiente', r.status === 200 && r.body.pendientes.length === 0);
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    filas = await q('SELECT documento FROM taceptacioneslegales WHERE cusuario = $1 ORDER BY documento', [luis.usuario.id]);
    check('el vendedor acepta los términos de negocio', filas.map((f) => f.documento).join() === 'privacidad,terminos-vendedor');
    r = await api('GET', '/api/legal/pendientes', null, A);
    check('el administrador no tiene documentos que aceptar', r.status === 200 && r.body.pendientes.length === 0);
    r = await api('GET', '/api/legal/pendientes');
    check('pendientes sin sesión: 401', r.status === 401);

    seccion('4. Versión nueva: hay que volver a aceptar');
    await q("UPDATE taceptacioneslegales SET version = '1.9' WHERE cusuario = $1 AND documento = 'terminos-cliente'", [ana.usuario.id]);
    r = await api('GET', '/api/legal/pendientes', null, ana.token);
    check('con una versión vieja aceptada, le aparece pendiente la nueva', r.body.pendientes.length === 1 && r.body.pendientes[0].id === 'terminos-cliente' && r.body.pendientes[0].version === versionDe('terminos-cliente') && !!r.body.pendientes[0].resumen, JSON.stringify(r.body));
    r = await api('POST', '/api/legal/aceptar', { documentos: [{ id: 'terminos-cliente', version: '1.9' }] }, ana.token);
    check('aceptar una versión que ya no es la vigente: 409', r.status === 409 && r.body.code === 'VERSIONDESACTUALIZADA');
    r = await api('POST', '/api/legal/aceptar', { documentos: [{ id: 'terminos-repartidor', version: versionDe('terminos-repartidor') }] }, ana.token);
    check('aceptar los términos de otro perfil: 400', r.status === 400 && r.body.code === 'DOCUMENTONOCORRESPONDE');
    r = await api('POST', '/api/legal/aceptar', { documentos: [] }, ana.token);
    check('sin documentos: 400', r.status === 400);
    r = await api('POST', '/api/legal/aceptar', { documentos: [{ id: 'terminos-cliente', version: versionDe('terminos-cliente') }], plataforma: 'android' }, ana.token);
    check('acepta la nueva y ya no queda nada pendiente', r.status === 200 && r.body.pendientes.length === 0, JSON.stringify(r.body));
    filas = await q("SELECT version, plataforma FROM taceptacioneslegales WHERE cusuario = $1 AND documento = 'terminos-cliente' ORDER BY saceptacion", [ana.usuario.id]);
    check('queda el historial: la versión vieja y la nueva', filas.length === 2 && filas[1].version === versionDe('terminos-cliente') && filas[1].plataforma === 'android');
    r = await api('POST', '/api/legal/aceptar', { documentos: [{ id: 'terminos-cliente', version: versionDe('terminos-cliente') }] }, ana.token);
    check('aceptar dos veces lo mismo no duplica', r.status === 200 && (await q("SELECT 1 FROM taceptacioneslegales WHERE cusuario = $1 AND documento = 'terminos-cliente'", [ana.usuario.id])).length === 2);
    r = await api('GET', '/api/admin/legal', null, A);
    const tc = r.body.documentos?.find((d) => d.id === 'terminos-cliente');
    check('el admin ve cuántas cuentas aceptaron cada versión', r.status === 200 && tc?.cuentas === 1 && tc.aceptaron === 1 && r.body.documentos.find((d) => d.id === 'privacidad')?.cuentas === 2, JSON.stringify(r.body));

    seccion('5. Eliminar la cuenta');
    // Ana tiene foto, dirección, un cambio de nombre (historial) y un pedido en curso
    await api('PUT', '/api/auth/profile', { nombre: 'Anita' }, ana.token);
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: await t.imagen(300, 300) }, ana.token);
    check('preparación: foto de perfil subida', r.status === 200, JSON.stringify(r.body));
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle secreta 123', latitud: -3.83, longitud: -78.76, tipo: 'DOM' }, ana.token)).body.direccion;
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Principal', latitud: -3.83, longitud: -78.76 }, luis.token);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, luis.token);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10 }, luis.token)).body.producto;
    const pedido = (await api('POST', '/api/pedidos', { negocioId: pizza.negocioId, direccionId: dir.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 1 }] }, ana.token)).body.pedido;
    check('preparación: pedido creado', !!pedido?.id);
    const persona = (await q(`SELECT cpersona FROM tusuarios WHERE cusuario = $1 AND fhasta = ${VIGENTE}`, [ana.usuario.id]))[0].cpersona;
    const fotoAntes = (await q(`SELECT carchivo_foto FROM tpersonas WHERE cpersona = $1 AND fhasta = ${VIGENTE}`, [persona]))[0].carchivo_foto;

    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'otra' }, ana.token);
    check('con la contraseña equivocada: 401', r.status === 401);
    r = await api('POST', '/api/auth/eliminar-cuenta', {}, ana.token);
    check('sin contraseña: 400', r.status === 400);
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, ana.token);
    check('con un pedido en curso no se puede: 409', r.status === 409 && r.body.code === 'PEDIDOENCURSO');
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, luis.token);
    check('el negocio tampoco, mientras tenga ese pedido en curso', r.status === 409 && r.body.code === 'PEDIDOENCURSO');
    await api('PATCH', `/api/mi-negocio/pedidos/${pedido.id}/estado`, { estado: 'rechazado', motivo: 'Sin stock por hoy' }, luis.token);

    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, A);
    check('el administrador no se elimina desde la app: 403', r.status === 403);
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, ana.token);
    check('sin pedidos en curso: la cuenta se elimina', r.status === 200 && r.body.eliminada === true, JSON.stringify(r.body));

    const personas = await q('SELECT nombres, apellidos, numerodocumento, correo, carchivo_foto FROM tpersonas WHERE cpersona = $1', [persona]);
    check('la persona y TODO su historial quedan sin nombre, cédula, correo ni foto', personas.length >= 2 && personas.every((p) => p.nombres === 'Cuenta' && p.correo.endsWith('@vallexpress.invalid') && p.numerodocumento.startsWith('ELIM') && p.carchivo_foto === null), JSON.stringify(personas));
    const telefonos = await q('SELECT numerotelefono FROM tpersonatelefonos WHERE cpersona = $1', [persona]);
    check('sus teléfonos se borran', telefonos.length > 0 && telefonos.every((x) => x.numerotelefono.startsWith('ELIM')));
    const direcciones = await q('SELECT direccion, latitud FROM tpersonadirecciones WHERE cpersona = $1', [persona]);
    check('sus direcciones guardadas se borran (también el historial)', direcciones.length > 0 && direcciones.every((d) => d.direccion === 'Dirección eliminada' && Number(d.latitud) === 0));
    check('su foto de perfil se borra (fila y archivo)', !!fotoAntes && (await q('SELECT 1 FROM tarchivos WHERE carchivo = $1', [fotoAntes])).length === 0);
    check('la cuenta queda dada de baja', (await q(`SELECT cestatususuario FROM tusuarios WHERE cusuario = $1 AND fhasta = ${VIGENTE}`, [ana.usuario.id]))[0].cestatususuario === '002');
    check('el pedido se conserva (registro contable)', (await q('SELECT 1 FROM tpedidos WHERE cpedido = $1', [pedido.id])).length > 0);
    check('sus sesiones se cierran', (await q('SELECT 1 FROM tsesiones WHERE cusuario = $1 AND frevocado IS NULL', [ana.usuario.id])).length === 0);
    r = await api('GET', '/api/auth/profile', null, ana.token);
    check('su token deja de servir', r.status === 401 || r.status === 403);
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    check('ya no puede iniciar sesión con su correo', r.status === 401);
    r = await api('POST', '/api/auth/refresh', { refreshToken: ana.refreshToken });
    check('ni renovar la sesión', r.status === 401 || r.status === 403);
    const otra = await t.registrar('ana@test.com', 'Ana', 'Paz', 'cliente');
    check('su correo queda libre para una cuenta nueva', !!otra.token && otra.usuario.id !== ana.usuario.id);
    check('en la auditoría queda la eliminación', (await q("SELECT 1 FROM tauditoria WHERE accion = 'CUENTAELIMINADA'")).length >= 1);

    seccion('6. Negocio con la suscripción vencida');
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, pedro.token);
    const dir2 = (await api('POST', '/api/direcciones', { direccion: 'Calle 2', latitud: -3.83, longitud: -78.76, tipo: 'DOM' }, otra.token)).body.direccion;
    const p2 = (await api('POST', '/api/pedidos', { negocioId: pizza.negocioId, direccionId: dir2.id, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 1 }] }, otra.token)).body.pedido;
    for (const e of ['confirmado', 'listo']) await api('PATCH', `/api/mi-negocio/pedidos/${p2.id}/estado`, { estado: e }, luis.token);
    for (const paso of ['aceptar', 'recogido', 'entregado']) await api('PATCH', `/api/repartidor/pedidos/${p2.id}/${paso}`, null, pedro.token);
    // Se cobra desde enero de 2025 y su negocio se aprobó hace 90 días: tiene meses vencidos
    await api('PUT', '/api/admin/suscripciones/config', { inicio: '2025-01' }, A);
    await q(`UPDATE tnegocios SET faprobacion = now() - interval '90 days' WHERE cusuario = $1 AND fhasta = ${VIGENTE}`, [luis.usuario.id]);
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, luis.token);
    check('con meses de suscripción vencidos no se puede: 409', r.status === 409 && r.body.code === 'SUSCRIPCIONPENDIENTE', JSON.stringify(r.body));
    const ubic = await q('SELECT COUNT(*)::int AS n FROM trepartidorubicaciones WHERE cusuario = $1', [pedro.usuario.id]);
    await api('PUT', '/api/repartidor/documentos/cedula_frente', { imagen: await t.imagen(600, 400, 'jpeg') }, pedro.token);
    const docAntes = (await q('SELECT carchivo FROM trepartidordocumentos WHERE cusuario = $1', [pedro.usuario.id]))[0]?.carchivo;
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'secreto1' }, pedro.token);
    check('el repartidor sin pedidos en curso sí puede', r.status === 200);
    check('sus documentos (cédula, etc.) se borran: filas y archivos', !!docAntes && (await q('SELECT 1 FROM trepartidordocumentos WHERE cusuario = $1', [pedro.usuario.id])).length === 0 && (await q('SELECT 1 FROM tarchivos WHERE carchivo = $1', [docAntes])).length === 0);
    check('su placa y sus recorridos se borran', (await q('SELECT 1 FROM trepartidores WHERE cusuario = $1 AND placa IS NOT NULL', [pedro.usuario.id])).length === 0 && (await q('SELECT 1 FROM trepartidorubicaciones WHERE cusuario = $1', [pedro.usuario.id])).length === 0, `ubicaciones antes: ${ubic[0].n}`);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
