// Prueba de extremo a extremo de los cambios del 2026-10-18:
//   VARIOS PERFILES por persona (cliente, vendedor y repartidor con la misma cédula y correo, nunca dos del mismo),
//   SUSCRIPCIÓN MENSUAL de vendedores y repartidores (en vez de la comisión): estado de cuenta, comprobante, revisión
//   del administrador, pago a mano y bloqueo por mes vencido; CALIFICACIÓN del negocio al repartidor, ADVERTENCIAS
//   del administrador, el repartidor con una entrega en curso no cierra sesión y RENOMBRARUSUARIO().
// Uso:  npm run test:suscripciones   (desde la carpeta backend, con Docker/Postgres en marcha)
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3098, bd: 'vallexpress_test_suscripciones' });
const { check, seccion, api, marca, codigoDe } = t;
const VIGENTE = "'2999-12-31 00:00:00-05'";

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());
    const { hashClave } = require('../src/shared/utils/clave');
    await q(`UPDATE tusuarios SET clavehash=$1 WHERE cusuario='admin' AND fhasta=${VIGENTE}`, [await hashClave('admin-secreta-1')]);
    const A = (await api('POST', '/api/auth/login', { email: 'admin', password: 'admin-secreta-1' })).body.token;
    // Verifica un correo para crear OTRO perfil (manda el perfil que está creando)
    const verificar = async (email, tipoUsuario) => {
      const desde = marca();
      const r = await api('POST', '/api/auth/send-verification', { email, nombre: 'X', tipoUsuario });
      if (r.status !== 200) return r;
      await api('POST', '/api/auth/verify-email', { email, code: await codigoDe(email, 'verificacion', desde) });
      return r;
    };
    const personaDe = async (usuario) => (await q(`SELECT cpersona FROM tusuarios WHERE cusuario=$1 AND fhasta=${VIGENTE}`, [usuario]))[0]?.cpersona;
    const datosDe = async (email) => (await q(`SELECT p.numerodocumento AS cedula, t.numerotelefono AS telefono FROM tpersonas p
      JOIN tpersonatelefonos t ON t.cpersona = p.cpersona AND t.fhasta = ${VIGENTE} AND t.esprincipal WHERE p.correo=$1 AND p.fhasta=${VIGENTE}`, [email]))[0];

    seccion('1. Preparación');
    const luis = await t.registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const L = luis.token;
    await api('PUT', '/api/mi-negocio/local', { direccion: 'Av. Amazonas', latitud: -0.18, longitud: -78.48 }, L);
    await api('PATCH', '/api/mi-negocio/estado', { abierto: true }, L);
    const pizza = (await api('POST', '/api/mi-negocio/productos', { nombre: 'Pizza', precio: 10 }, L)).body.producto;
    const negocioId = pizza.negocioId;
    const carlos = await t.registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    let C = carlos.token;
    const dir = (await api('POST', '/api/direcciones', { direccion: 'Calle 1', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, C)).body.direccion;
    const pedro = await t.registrar('pedro@test.com', 'Pedro', 'Vera', 'repartidor', { vehiculo: 'Moto', placa: 'ABC1234' });
    const P = pedro.token;
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    const pedir = (token = C, direccionId = dir.id) => api('POST', '/api/pedidos', { negocioId, direccionId, metodoPago: 'efectivo', productos: [{ productoId: pizza.id, cantidad: 1 }] }, token);
    const listo = async (token = C, direccionId = dir.id) => {
      const p = (await pedir(token, direccionId)).body.pedido;
      for (const e of ['confirmado', 'listo']) await api('PATCH', `/api/mi-negocio/pedidos/${p.id}/estado`, { estado: e }, L);
      return p;
    };
    check('negocio, cliente y repartidor listos', !!pizza?.id && !!dir?.id && !!P);

    seccion('2. Varios perfiles con la misma cédula y el mismo correo');
    const dc = await datosDe('carlos@test.com');
    let r = await api('GET', '/api/auth/check-email/carlos@test.com?tipo=repartidor');
    check('el correo de un cliente está libre para crear su perfil de repartidor (otroPerfil)', r.status === 200 && r.body.exists === false && r.body.otroPerfil === true, JSON.stringify(r.body));
    r = await api('GET', `/api/auth/check-email/carlos@test.com?tipo=repartidor&cedula=${t.cedula(17, 3901)}`);
    check('con otra cédula, el correo avisa desde el principio: otraCedula', r.body.exists === true && r.body.otraCedula === true, JSON.stringify(r.body));
    r = await api('GET', `/api/auth/check-email/carlos@test.com?tipo=repartidor&cedula=${dc.cedula}`);
    check('con su misma cédula: libre para el perfil nuevo', r.body.exists === false && r.body.otroPerfil === true && r.body.otraCedula === false, JSON.stringify(r.body));
    r = await api('GET', `/api/auth/check-cedula/${dc.cedula}?tipo=cliente`);
    check('pero no para otra cuenta de cliente', r.body.exists === true);
    r = await api('GET', '/api/auth/check-email/carlos@test.com');
    check('sin perfil (versiones viejas de la app) sigue diciendo que existe', r.body.exists === true);
    r = await api('POST', '/api/auth/send-verification', { email: 'carlos@test.com', nombre: 'Carlos' });
    check('código sin perfil a un correo registrado: 409 EMAILDUPLICADO', r.status === 409 && r.body.code === 'EMAILDUPLICADO');
    r = await api('POST', '/api/auth/send-verification', { email: 'carlos@test.com', nombre: 'Carlos', tipoUsuario: 'cliente' });
    check('código para el perfil que ya tiene: 409 PERFILDUPLICADO', r.status === 409 && r.body.code === 'PERFILDUPLICADO', JSON.stringify(r.body));
    r = await verificar('carlos@test.com', 'repartidor');
    check('código para el perfil nuevo (repartidor): 200', r.status === 200);
    const registro = (extra) => api('POST', '/api/auth/register', {
      nombre: 'Carlos', apellido: 'Ruiz', email: 'carlos@test.com', telefono: dc.telefono, cedula: dc.cedula, password: 'secreto1',
      tipoUsuario: 'repartidor', vehiculo: 'bicicleta', aceptaTerminos: true, ...extra,
    });
    r = await registro({ cedula: t.cedula(17, 3900) });
    check('mismo correo con otra cédula: 409 EMAILDUPLICADO', r.status === 409 && r.body.code === 'EMAILDUPLICADO', JSON.stringify(r.body));
    r = await registro();
    const carlosRep = r.body.usuario;
    check('mismo correo y cédula: se crea su cuenta de repartidor (otro usuario)', r.status === 201 && carlosRep?.tipoUsuario === 'repartidor' && carlosRep.id !== carlos.usuario.id, JSON.stringify(r.body).slice(0, 300));
    check('las dos cuentas son de la MISMA persona', String(await personaDe(carlosRep.id)) === String(await personaDe(carlos.usuario.id)));
    check('no se duplicó el teléfono', (await q(`SELECT COUNT(*)::int AS n FROM tpersonatelefonos WHERE numerotelefono=$1 AND fhasta=${VIGENTE}`, [dc.telefono]))[0].n === 1);
    await verificar('carlos@test.com', 'vendedor');
    r = await registro({ tipoUsuario: 'repartidor' });
    check('el mismo perfil dos veces: 409 PERFILDUPLICADO', r.status === 409 && r.body.code === 'PERFILDUPLICADO');
    await verificar('otro@test.com', 'cliente');
    r = await api('POST', '/api/auth/register', { nombre: 'Otro', apellido: 'Más', email: 'otro@test.com', telefono: '0997777777', cedula: dc.cedula, password: 'secreto1', tipoUsuario: 'cliente', aceptaTerminos: true });
    check('su cédula con otro correo: 409 CEDULADUPLICADA', r.status === 409 && r.body.code === 'CEDULADUPLICADA', JSON.stringify(r.body));

    seccion('3. Iniciar sesión con varias cuentas');
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'secreto1' });
    check('misma clave en las dos: 409 ELEGIRCUENTA con las dos cuentas', r.status === 409 && r.body.code === 'ELEGIRCUENTA' && r.body.cuentas?.length === 2 && r.body.cuentas.some((c) => c.tipoUsuario === 'repartidor'), JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'secreto1', tipoUsuario: 'repartidor' });
    const CR = r.body.token;
    check('eligiendo el perfil entra a esa cuenta', r.status === 200 && r.body.usuario.tipoUsuario === 'repartidor' && r.body.usuario.id === carlosRep.id);
    r = await api('POST', '/api/auth/login', { email: carlosRep.id, password: 'secreto1' });
    check('con su usuario entra directo', r.status === 200 && r.body.usuario.id === carlosRep.id);
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'secreto1', passwordNueva: 'reparto99', confirmarPassword: 'reparto99' }, CR);
    check('cambia la clave solo de su cuenta de repartidor', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'reparto99' });
    check('con claves distintas el correo entra a la cuenta de esa clave', r.status === 200 && r.body.usuario.id === carlosRep.id, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'secreto1' });
    check('y con la otra clave, a la de cliente', r.status === 200 && r.body.usuario.id === carlos.usuario.id);
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'mala-clave' });
    check('clave que no es de ninguna: 401', r.status === 401);
    let desde = marca();
    await api('POST', '/api/auth/forgot-password', { email: 'carlos@test.com' });
    const tokenReset = (await api('POST', '/api/auth/verify-reset-code', { email: 'carlos@test.com', code: await codigoDe('carlos@test.com', 'reset', desde) })).body.resetToken;
    r = await api('POST', '/api/auth/reset-password', { resetToken: tokenReset, newPassword: 'nueva-clave-1', confirmarPassword: 'nueva-clave-1' });
    check('recuperar la clave por correo: 200', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'nueva-clave-1' });
    check('la clave nueva queda en TODAS sus cuentas (pide elegir)', r.status === 409 && r.body.cuentas?.length === 2);
    const C2 = (await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'nueva-clave-1', tipoUsuario: 'cliente' })).body.token;
    const CR2 = (await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'nueva-clave-1', tipoUsuario: 'repartidor' })).body.token;
    C = C2;      // restablecer la clave cerró sus sesiones anteriores
    await api('PUT', '/api/auth/profile', { nombre: 'Carlitos', apellido: 'Ruiz', telefono: dc.telefono }, C2);
    r = await api('GET', '/api/auth/profile', null, CR2);
    check('los datos de la persona son los mismos en sus cuentas (cambió el nombre desde la de cliente)', r.body.usuario?.nombre === 'Carlitos', JSON.stringify(r.body));
    r = await api('GET', '/api/auth/cuentas', null, C2);
    check('ve sus dos cuentas para cambiar entre ellas (la actual marcada)', r.status === 200 && r.body.cuentas.length === 2 && r.body.cuentas.find((x) => x.actual)?.tipoUsuario === 'cliente' && r.body.cuentas.some((x) => x.tipoUsuario === 'repartidor' && !x.actual), JSON.stringify(r.body));
    r = await api('GET', '/api/auth/cuentas', null, L);
    check('quien tiene una sola cuenta ve solo la suya', r.body.cuentas?.length === 1);
    await api('POST', '/api/notificaciones/dispositivo', { token: 'celu-carlos' }, C2);
    await api('POST', '/api/notificaciones/dispositivo', { token: 'celu-carlos' }, CR2);
    check('su celular queda registrado para sus dos cuentas (recibe los avisos de ambas)', (await q("SELECT cusuario FROM tdispositivos WHERE tokenfcm='celu-carlos' ORDER BY cusuario")).length === 2);
    await api('POST', '/api/notificaciones/dispositivo', { token: 'celu-carlos' }, L);
    check('si el celular pasa a otra persona, Carlos deja de recibir avisos en él', (await q("SELECT cusuario FROM tdispositivos WHERE tokenfcm='celu-carlos'")).map((x) => x.cusuario).join() === luis.usuario.id);
    await q("DELETE FROM tdispositivos WHERE tokenfcm='celu-carlos'");

    seccion('4. Nadie se atiende a sí mismo');
    const propio = await listo(C2);
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, CR2);
    r = await api('PATCH', `/api/repartidor/pedidos/${propio.id}/aceptar`, null, CR2);
    check('el repartidor no acepta el pedido que hizo con su cuenta de cliente: 409 PEDIDOPROPIO', r.status === 409 && r.body.code === 'PEDIDOPROPIO', JSON.stringify(r.body));
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: false }, CR2);
    const dl = await datosDe('luis@test.com');
    await verificar('luis@test.com', 'cliente');
    r = await api('POST', '/api/auth/register', { nombre: 'Luis', apellido: 'Mora', email: 'luis@test.com', telefono: dl.telefono, cedula: dl.cedula, password: 'secreto1', tipoUsuario: 'cliente', aceptaTerminos: true });
    const LC = r.body.token;
    check('el vendedor también crea su cuenta de cliente', r.status === 201 && r.body.usuario.tipoUsuario === 'cliente');
    const dirL = (await api('POST', '/api/direcciones', { direccion: 'Casa Luis', latitud: -0.19, longitud: -78.49, tipo: 'DOM' }, LC)).body.direccion;
    r = await pedir(LC, dirL.id);
    check('pero no le pide a su propio negocio: 409 PEDIDOPROPIO', r.status === 409 && r.body.code === 'PEDIDOPROPIO', JSON.stringify(r.body));

    seccion('5. Suscripción: al aprobarlo, el primer mes es gratis');
    r = await api('GET', '/api/suscripcion', null, P);
    const s0 = r.body;
    check('el repartidor ve su suscripción: $10 al mes, aún no debe nada', r.status === 200 && s0.aplica === true && s0.tipo === 'repartidor' && s0.cuota === 10 && s0.saldoPendiente === 0 && s0.bloqueado === false, JSON.stringify(s0).slice(0, 400));
    check('su primer mes es el siguiente (o el inicio del cobro) y se puede adelantar', s0.meses.length === 1 && s0.meses[0].estado === 'proximo' && /^\d{4}-\d{2}-01$/.test(s0.meses[0].mes), JSON.stringify(s0.meses));
    r = await api('GET', '/api/suscripcion', null, C);
    check('un cliente no tiene suscripción: 403', r.status === 403);
    r = await api('GET', '/api/suscripcion', null, L);
    check('el vendedor también la ve', r.status === 200 && r.body.tipo === 'vendedor' && r.body.cuota === 10);

    seccion('6. Mes vencido: el repartidor no se conecta y el negocio no recibe pedidos');
    // Se cobra desde el mes pasado y los dos se aprobaron hace 90 días: el mes pasado está vencido
    const espera = await listo();
    const [{ mespasado }] = await q("SELECT to_char(date_trunc('month', now() AT TIME ZONE 'America/Guayaquil') - interval '1 month', 'YYYY-MM') AS mespasado");
    r = await api('PUT', '/api/admin/suscripciones/config', { inicio: mespasado }, A);
    check('el admin cambia desde qué mes se cobra', r.status === 200 && r.body.config.inicio === `${mespasado}-01`, JSON.stringify(r.body));
    await q(`UPDATE trepartidores SET faprobacion = now() - interval '90 days' WHERE cusuario = $1 AND fhasta = ${VIGENTE}`, [pedro.usuario.id]);
    await q(`UPDATE tnegocios SET faprobacion = now() - interval '90 days' WHERE cusuario = $1 AND fhasta = ${VIGENTE}`, [luis.usuario.id]);
    r = await api('GET', '/api/suscripcion', null, P);
    const vencido = r.body.meses.find((m) => m.mes === `${mespasado}-01`);
    check('el mes pasado aparece vencido y queda bloqueado', vencido?.estado === 'vencido' && r.body.bloqueado === true && r.body.saldoPendiente >= 10, JSON.stringify(r.body.meses));
    r = await api('PATCH', `/api/repartidor/pedidos/${espera.id}/aceptar`, null, P);
    check('no acepta pedidos: 403 SUSCRIPCIONVENCIDA', r.status === 403 && r.body.code === 'SUSCRIPCIONVENCIDA', JSON.stringify(r.body));
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: false }, P);
    r = await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    check('ni se conecta: 403 SUSCRIPCIONVENCIDA', r.status === 403 && r.body.code === 'SUSCRIPCIONVENCIDA');
    r = await pedir();
    check('el negocio con la suscripción vencida no recibe pedidos: 409', r.status === 409 && r.body.code === 'NEGOCIOCONDEUDA');
    r = await api('GET', `/api/negocios/${negocioId}`, null, C);
    check('y la app lo muestra sin aceptar pedidos', r.body.negocio?.aceptaPedidos === false);
    r = await api('GET', '/api/admin/resumen', null, A);
    check('el resumen del admin cuenta las suscripciones vencidas', r.body.suscripcionesVencidas === 2, JSON.stringify(r.body.suscripcionesVencidas));

    seccion('7. Comprobante: en revisión no bloquea');
    const porPagar = (await api('GET', '/api/suscripcion', null, P)).body.meses.filter((m) => ['vencido', 'por_pagar'].includes(m.estado));
    const img = await t.imagen(500, 700, 'jpeg');
    r = await api('POST', '/api/suscripcion/comprobante', { mes: '2020-01', imagen: img }, P);
    check('un mes que no está en su cuenta: 400', r.status === 400);
    for (const m of porPagar) r = await api('POST', '/api/suscripcion/comprobante', { mes: m.mes.slice(0, 7), imagen: img, referencia: `TRF-${m.mes.slice(5, 7)}` }, P);
    check('sube el comprobante de cada mes por pagar: 201', r.status === 201 && r.body.enRevision === porPagar.length && r.body.bloqueado === false, JSON.stringify(r.body).slice(0, 300));
    r = await api('POST', '/api/suscripcion/comprobante', { mes: porPagar[0].mes, imagen: img }, P);
    check('el mismo mes otra vez: 409 COMPROBANTEENREVISION', r.status === 409 && r.body.code === 'COMPROBANTEENREVISION');
    r = await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    check('con el comprobante en revisión ya se conecta', r.status === 200);
    check('los administradores reciben "Comprobante por revisar"', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario='admin' AND tipo='comprobante_nuevo'")).length === porPagar.length);

    seccion('8. El administrador revisa');
    r = await api('GET', '/api/admin/suscripciones', null, A);
    const comprobantes = r.body.comprobantes || [];
    const fila = (r.body.suscriptores || []).find((s) => s.usuario === pedro.usuario.id);
    check('ve los comprobantes con su foto y a quién son', r.status === 200 && comprobantes.length === porPagar.length && comprobantes.every((c) => c.imagen && c.usuario === pedro.usuario.id && c.monto === 10), JSON.stringify(comprobantes).slice(0, 300));
    check('y la lista de quienes pagan (Pedro en revisión, Luis vencido)', fila?.enRevision === porPagar.length && r.body.suscriptores.find((s) => s.usuario === luis.usuario.id)?.bloqueado === true, JSON.stringify(r.body.suscriptores));
    r = await api('POST', `/api/admin/comprobantes/${comprobantes[0].id}/rechazar`, { motivo: 'no' }, A);
    check('rechazar sin un motivo claro: 400', r.status === 400);
    r = await api('POST', `/api/admin/comprobantes/${comprobantes[0].id}/rechazar`, { motivo: 'La imagen no se lee' }, A);
    const rech = r.body.meses?.find((m) => m.mes === comprobantes[0].mes);
    check('rechazado: el mes vuelve a deberse y muestra el motivo', r.status === 200 && ['vencido', 'por_pagar'].includes(rech?.estado) && rech.rechazado?.motivoRechazo === 'La imagen no se lee', JSON.stringify(rech));
    check('al repartidor le llega el aviso', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='comprobante_rechazado'", [pedro.usuario.id])).length === 1);
    r = await api('POST', `/api/admin/comprobantes/${comprobantes[0].id}/aprobar`, null, A);
    check('un comprobante ya revisado no se vuelve a revisar: 409', r.status === 409 && r.body.code === 'COMPROBANTEREVISADO');
    r = await api('POST', '/api/suscripcion/comprobante', { mes: comprobantes[0].mes, imagen: img, referencia: 'TRF-OK' }, P);
    check('sube uno nuevo', r.status === 201);
    const pendientes = (await api('GET', '/api/admin/suscripciones', null, A)).body.comprobantes;
    r = await api('POST', `/api/admin/comprobantes/${pendientes[0].id}/aprobar`, null, L);
    check('un vendedor no aprueba comprobantes: 403', r.status === 403);
    for (const c of pendientes) r = await api('POST', `/api/admin/comprobantes/${c.id}/aprobar`, null, A);
    check('aprobados: los meses quedan pagados y está al día', r.status === 200 && r.body.saldoPendiente === 0 && r.body.bloqueado === false && r.body.meses.filter((m) => m.estado === 'pagado').length === porPagar.length, JSON.stringify(r.body.meses));
    check('al día, se le ofrece adelantar el mes siguiente', r.body.meses[0].estado === 'proximo');
    check('recibe "Recibimos tu pago"', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario=$1 AND tipo='suscripcion_pagada'", [pedro.usuario.id])).length === porPagar.length);

    seccion('9. Pago a mano (efectivo) y lo cobrado');
    const mesesLuis = (await api('GET', `/api/admin/suscripciones/${luis.usuario.id}`, null, A)).body.meses.filter((m) => ['vencido', 'por_pagar'].includes(m.estado));
    for (const m of mesesLuis) r = await api('POST', `/api/admin/suscripciones/${luis.usuario.id}/pagos`, { mes: m.mes.slice(0, 7), referencia: 'Efectivo' }, A);
    check('el admin registra los pagos en efectivo del vendedor', r.status === 201 && r.body.saldoPendiente === 0 && r.body.bloqueado === false, JSON.stringify(r.body).slice(0, 300));
    r = await api('POST', `/api/admin/suscripciones/${luis.usuario.id}/pagos`, { mes: mesesLuis[0].mes.slice(0, 7) }, A);
    check('un mes ya pagado: 409 YAPAGADO', r.status === 409 && r.body.code === 'YAPAGADO');
    r = await api('POST', `/api/admin/suscripciones/${carlos.usuario.id}/pagos`, { mes: mesesLuis[0].mes.slice(0, 7) }, A);
    check('a un cliente no se le registran pagos: 404', r.status === 404);
    r = await pedir();
    check('el negocio vuelve a recibir pedidos', r.status === 201);
    const cobradoEsperado = 10 * (porPagar.length + mesesLuis.length);
    r = await api('GET', '/api/admin/resumen', null, A);
    check(`lo cobrado hoy es $${cobradoEsperado} y no queda nadie vencido`, r.body.cobrado?.hoy === cobradoEsperado && r.body.suscripcionesVencidas === 0 && r.body.comprobantesPorRevisar === 0, JSON.stringify(r.body.cobrado));
    r = await api('GET', '/api/admin/resumen/ganancia', null, A);
    check('la "Ganancia" del resumen son las suscripciones cobradas', r.body.total?.valor === cobradoEsperado && r.body.secciones[0].filas.length === porPagar.length + mesesLuis.length, JSON.stringify(r.body).slice(0, 300));
    r = await api('PUT', '/api/admin/suscripciones/config', { cuotaRepartidor: 12, diasGracia: 40 }, A);
    check('día límite fuera de rango: 400', r.status === 400);
    r = await api('PUT', '/api/admin/suscripciones/config', { cuotaRepartidor: 12 }, A);
    check('cambia la cuota del repartidor', r.status === 200 && r.body.config.cuotaRepartidor === 12 && r.body.config.cuotaVendedor === 10);
    r = await api('GET', '/api/suscripcion', null, P);
    check('el próximo mes se cobra con la cuota nueva; lo pagado no cambia', r.body.meses[0].monto === 12 && r.body.meses.filter((m) => m.estado === 'pagado').every((m) => m.monto === 10), JSON.stringify(r.body.meses));
    r = await api('GET', '/api/legal/terminos-repartidor');
    check('los términos del repartidor muestran la cuota vigente', JSON.stringify(r.body).includes('$12.00'));

    seccion('10. El negocio califica al repartidor');
    await api('PATCH', '/api/repartidor/disponibilidad', { disponible: true }, P);
    r = await api('PATCH', `/api/repartidor/pedidos/${espera.id}/aceptar`, null, P);
    check('ya al día, acepta el pedido', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', `/api/mi-negocio/pedidos/${espera.id}/calificar-repartidor`, { puntuacion: 4 }, L);
    check('antes de que lo recoja no se califica: 409', r.status === 409 && r.body.code === 'PEDIDONORECOGIDO');

    seccion('11. Con una entrega en curso no cierra sesión');
    r = await api('POST', '/api/auth/logout', { refreshToken: pedro.refreshToken });
    check('cerrar sesión con el pedido aceptado: 409 ENTREGAENCURSO', r.status === 409 && r.body.code === 'ENTREGAENCURSO' && r.body.pedidoId === espera.id, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/logout-all', null, P);
    check('tampoco en todos los equipos: 409', r.status === 409 && r.body.code === 'ENTREGAENCURSO');
    await api('PATCH', `/api/repartidor/pedidos/${espera.id}/recogido`, null, P);
    r = await api('POST', '/api/auth/logout', { refreshToken: pedro.refreshToken });
    check('ni con el pedido recogido', r.status === 409);

    r = await api('POST', `/api/mi-negocio/pedidos/${espera.id}/calificar-repartidor`, { puntuacion: 2, comentario: 'Llegó tarde y fue grosero' }, L);
    check('recogido: el negocio lo califica', r.status === 200 && r.body.pedido?.calificacionRepartidorNegocio?.puntuacion === 2, JSON.stringify(r.body).slice(0, 300));
    r = await api('POST', `/api/mi-negocio/pedidos/${espera.id}/calificar-repartidor`, { puntuacion: 5 }, L);
    check('dos veces no: 409 YACALIFICADO', r.status === 409 && r.body.code === 'YACALIFICADO');
    r = await api('POST', `/api/mi-negocio/pedidos/${espera.id}/calificar-repartidor`, { puntuacion: 5 }, C);
    check('el cliente no usa la ruta del negocio: 403', r.status === 403);
    check('una calificación baja (2★) avisa a los administradores', (await q("SELECT 1 FROM tnotificaciones WHERE cusuario='admin' AND tipo='calificacion_baja'")).length === 1);
    await api('PATCH', `/api/repartidor/pedidos/${espera.id}/entregado`, null, P);
    r = await api('POST', `/api/pedidos/${espera.id}/calificar`, { puntuacion: 5, destino: 'repartidor', comentario: 'Muy amable' }, C);
    check('el cliente también lo califica', r.status === 200 && r.body.pedido.calificacionRepartidor?.puntuacion === 5, JSON.stringify(r.body).slice(0, 200));
    check('el cliente no ve lo que dijo el negocio', !('calificacionRepartidorNegocio' in r.body.pedido));
    const est = (await q('SELECT calificacion, numerocalificaciones FROM trepartidoresestado WHERE cusuario=$1', [pedro.usuario.id]))[0];
    check('su promedio junta las dos: 3.5 con 2 calificaciones', Number(est.calificacion) === 3.5 && est.numerocalificaciones === 2, JSON.stringify(est));
    r = await api('POST', '/api/auth/logout', { refreshToken: pedro.refreshToken });
    check('entregado: ya puede cerrar sesión', r.status === 200);
    check('y al cerrar sesión deja de estar "En línea"', (await q('SELECT estadisponible FROM trepartidoresestado WHERE cusuario=$1', [pedro.usuario.id]))[0].estadisponible === false);
    const P2 = (await api('POST', '/api/auth/login', { email: 'pedro@test.com', password: 'secreto1' })).body.token;

    seccion('12. Reputación y advertencias');
    r = await api('GET', `/api/admin/repartidores/${pedro.usuario.id}/reputacion`, null, A);
    check('el admin ve su reputación: clientes y negocios, con quién calificó', r.status === 200 && r.body.total === 2 && r.body.clientes.total === 1 && r.body.negocios.promedio === 2 && r.body.bajas === 1 && r.body.calificaciones.some((c) => c.autor === 'Pizzería Luis'), JSON.stringify(r.body).slice(0, 400));
    r = await api('POST', `/api/admin/repartidores/${pedro.usuario.id}/advertencias`, { motivo: 'corto' }, A);
    check('advertencia sin motivo claro: 400', r.status === 400);
    r = await api('POST', `/api/admin/repartidores/${pedro.usuario.id}/advertencias`, { motivo: 'Un negocio reportó que llegaste tarde y fuiste grosero' }, A);
    check('el admin le envía una advertencia', r.status === 201 && r.body.advertencias.length === 1);
    const aviso = (await q("SELECT titulo, mensaje FROM tnotificaciones WHERE cusuario=$1 AND tipo='advertencia_repartidor'", [pedro.usuario.id]))[0];
    check('al repartidor le llega la notificación (mejorar o será dado de baja)', !!aviso && aviso.mensaje.includes('dada de baja'), JSON.stringify(aviso));
    r = await api('GET', '/api/repartidor/reputacion', null, P2);
    check('el repartidor ve su reputación y la advertencia, sin saber quién lo calificó', r.status === 200 && r.body.promedio === 3.5 && r.body.advertencias.length === 1 && r.body.calificaciones.every((c) => !('autor' in c)), JSON.stringify(r.body).slice(0, 300));
    r = await api('POST', `/api/admin/repartidores/${carlos.usuario.id}/advertencias`, { motivo: 'No es repartidor, no aplica esto' }, A);
    check('a quien no es repartidor: 404', r.status === 404);

    seccion('13. Eliminar una de sus cuentas');
    r = await api('POST', '/api/auth/eliminar-cuenta', { password: 'nueva-clave-1' }, CR2);
    check('Carlos elimina su cuenta de repartidor', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'carlos@test.com', password: 'nueva-clave-1' });
    check('su cuenta de cliente sigue: entra directo (ya no pide elegir)', r.status === 200 && r.body.usuario.id === carlos.usuario.id && r.body.usuario.nombre === 'Carlitos', JSON.stringify(r.body).slice(0, 200));
    check('la cuenta eliminada quedó en una persona anónima', String(await personaDe(carlosRep.id)) !== String(await personaDe(carlos.usuario.id)) && (await q(`SELECT p.correo FROM tusuarios u JOIN tpersonas p ON p.cpersona = u.cpersona AND p.fhasta = ${VIGENTE} WHERE u.cusuario=$1 AND u.fhasta = ${VIGENTE}`, [carlosRep.id]))[0].correo.startsWith('eliminada-'));
    check('y en el historial de la cuenta tampoco queda su persona', (await q('SELECT 1 FROM tusuarios WHERE cusuario=$1 AND cpersona=$2', [carlosRep.id, await personaDe(carlos.usuario.id)])).length === 0);
    await verificar('carlos@test.com', 'repartidor');
    r = await registro({ password: 'otra-clave-9', vehiculo: 'a_pie' });
    check('puede volver a crear su perfil de repartidor', r.status === 201 && r.body.usuario.tipoUsuario === 'repartidor', JSON.stringify(r.body).slice(0, 200));

    seccion('14. Renombrar un usuario (RENOMBRARUSUARIO)');
    let error = null;
    try { await q(`UPDATE tusuarios SET cusuario = 'luisito' WHERE cusuario = $1 AND fhasta = ${VIGENTE}`, [luis.usuario.id]); } catch (e) { error = e.message; }
    check('un UPDATE suelto del usuario se rechaza (dejaría las otras tablas con el viejo)', !!error && error.includes('RENOMBRARUSUARIO'), error);
    await q('SELECT RENOMBRARUSUARIO($1, $2)', [luis.usuario.id, 'luisito']);
    check('con la función se cambia en todas partes y el viejo desaparece', (await q('SELECT 1 FROM tusuariosid WHERE cusuario=$1', [luis.usuario.id])).length === 0
      && (await q(`SELECT 1 FROM tnegocios WHERE cusuario='luisito' AND fhasta=${VIGENTE}`)).length === 1
      && (await q("SELECT 1 FROM tsuscripcionpagos WHERE cusuario='luisito'")).length === mesesLuis.length
      && (await q("SELECT 1 FROM tcalificaciones WHERE cusuario='luisito'")).length === 1);
    check('también su historial', (await q('SELECT 1 FROM tusuarios WHERE cusuario=$1', [luis.usuario.id])).length === 0 && (await q("SELECT 1 FROM tusuarios WHERE cusuario='luisito'")).length >= 1);
    r = await api('POST', '/api/auth/login', { email: 'luisito', password: 'secreto1' });
    check('entra con el usuario nuevo', r.status === 200 && r.body.usuario.id === 'luisito');
    r = await api('GET', '/api/auth/profile', null, L);
    check('su sesión vieja ya no sirve (hay que volver a entrar)', r.status === 401 || r.status === 404, JSON.stringify(r.body));
    error = null;
    try { await q('SELECT RENOMBRARUSUARIO($1, $2)', ['luisito', pedro.usuario.id]); } catch (e) { error = e.message; }
    check('no se puede usar el usuario de otra persona', !!error && error.includes('otra persona'), error);
  } catch (e) {
    return t.finalizar(e);
  }
  return t.finalizar();
})();
