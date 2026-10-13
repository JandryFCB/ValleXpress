// Prueba de extremo a extremo del módulo auth sobre las tablas nuevas (database/migraciones).
// Uso:  npm run test:auth   (desde la carpeta backend, con Docker/Postgres en marcha)
//
// Crea su PROPIA base temporal (con las migraciones), levanta el servidor contra ella, recorre el flujo completo como
// lo haría la app (registro, login, sesión persistente, recuperar clave...) y al terminar borra todo.
// NO toca la base de desarrollo.
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const crearArnes = require('./arnes');

const t = crearArnes({ puerto: 3099, bd: 'vallexpress_test_auth' });
const { check, seccion, api, cedula } = t;
const sha256 = (x) => crypto.createHash('sha256').update(x).digest('hex');
const VIGENTE = "'2999-12-31 00:00:00-05'";

// Verifica el correo (leyendo el código de la consola del servidor) y devuelve la respuesta de verify-email
async function verificar(email, nombre = 'Test') {
  const desde = t.marca();
  const env = await api('POST', '/api/auth/send-verification', { email, nombre });
  if (env.status !== 200) return { env };
  const code = await t.codigoDe(email.toLowerCase(), 'verificacion', desde);
  return { env, code, ver: await api('POST', '/api/auth/verify-email', { email, code }) };
}

let contador = 0;
// Verifica el correo y registra a un cliente. Devuelve la respuesta del registro.
async function registrarCliente(email, nombre, apellido, extra = {}) {
  contador += 1;
  await verificar(email, nombre);
  return api('POST', '/api/auth/register', {
    nombre, apellido, email, telefono: `0998${String(contador).padStart(6, "0")}`, cedula: cedula(17, 2000 + contador),
    password: 'secreto1', tipoUsuario: 'cliente', dispositivo: 'Prueba', plataforma: 'android', ...extra,
  });
}

(async () => {
  let q;
  try {
    ({ q } = await t.iniciar());

    seccion('1. Servidor y formato de respuestas');
    let r = await api('GET', '/api/health');
    check('health responde 200', r.status === 200);
    r = await api('GET', '/api/no-existe');
    check('ruta inexistente: 404 con "error" en texto y code', r.status === 404 && typeof r.body.error === 'string' && r.body.code === 'RUTANOENCONTRADA', JSON.stringify(r.body));

    seccion('2. Validación y consultas en tiempo real');
    r = await api('GET', `/api/auth/check-cedula/${cedula(17, 1)}`);
    check('cédula libre', r.status === 200 && r.body.exists === false);
    r = await api('GET', '/api/auth/check-cedula/1234567890');
    check('cédula inválida: 400 con mensaje claro', r.status === 400 && /Cédula inválida/.test(r.body.error), JSON.stringify(r.body));
    r = await api('POST', '/api/auth/register', { nombre: 'A', apellido: 'B', email: 'malo', telefono: '123', cedula: '1', password: '12', tipoUsuario: 'cliente' });
    check('registro inválido: 400, primer mensaje en "error" y lista en "errors"', r.status === 400 && typeof r.body.error === 'string' && Array.isArray(r.body.errors) && r.body.errors.length >= 3);

    seccion('3. El registro exige email verificado (en el servidor)');
    r = await api('POST', '/api/auth/register', { nombre: 'Ana', apellido: 'Pérez', email: 'Ana@Test.com', telefono: '0991000001', cedula: cedula(17, 1001), password: 'secreto1', tipoUsuario: 'cliente' });
    check('sin verificar el email: 403 EMAILNOVERIFICADO', r.status === 403 && r.body.code === 'EMAILNOVERIFICADO', JSON.stringify(r.body));

    seccion('4. Verificación de email');
    let desde = t.marca();
    r = await api('POST', '/api/auth/send-verification', { email: 'Ana@Test.com', nombre: 'Ana' });
    check('enviar código: 200', r.status === 200, JSON.stringify(r.body));
    const codAna = await t.codigoDe('ana@test.com', 'verificacion', desde);
    check('el código es de 6 dígitos y va al email normalizado (minúsculas)', /^\d{6}$/.test(codAna || ''));
    r = await api('POST', '/api/auth/send-verification', { email: 'ana@test.com' });
    check('reenvío inmediato: 429 con retryAfter (espera de 60 s)', r.status === 429 && r.body.retryAfter > 0, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/verify-email', { email: 'ana@test.com', code: codAna === '000000' ? '111111' : '000000' });
    check('código incorrecto: 400 CODIGOINCORRECTO', r.status === 400 && r.body.code === 'CODIGOINCORRECTO');
    r = await api('POST', '/api/auth/verify-email', { email: 'ana@test.com', code: '12' });
    check('código mal formado: 400 "debe tener 6 dígitos"', r.status === 400 && /6 dígitos/.test(r.body.error));
    r = await api('POST', '/api/auth/verify-email', { email: 'ana@test.com', code: codAna });
    check('código correcto: verified=true', r.status === 200 && r.body.verified === true, JSON.stringify(r.body));
    let fila = (await q("SELECT codigohash, cpropositocodigo FROM tcodigosverificacion WHERE correo='ana@test.com'"))[0];
    check('en la BD el código va con hash (bcrypt) y propósito 001', fila.codigohash.startsWith('$2') && fila.cpropositocodigo === '001');

    seccion('5. Registro de cliente');
    r = await api('POST', '/api/auth/register', { nombre: 'Ana', apellido: 'Pérez', email: 'Ana@Test.com', telefono: '0991000001', cedula: cedula(17, 1001), password: 'secreto1', tipoUsuario: 'cliente', dispositivo: 'Pixel 7', plataforma: 'android' });
    check('registro: 201', r.status === 201, JSON.stringify(r.body));
    const ana = r.body;
    check('devuelve token de acceso, refreshToken y expiresIn=900', !!ana.token && !!ana.refreshToken && ana.expiresIn === 900);
    check('usuario con el formato de la app (tipoUsuario, verificado, cédula)', ana.usuario?.tipoUsuario === 'cliente' && ana.usuario?.verificado === true && ana.usuario?.cedula === cedula(17, 1001));
    check('NO devuelve el hash de la clave', !JSON.stringify(ana).includes('passwordHash') && !JSON.stringify(ana).includes('$2'));
    const persona = (await q(`SELECT * FROM tpersonas WHERE correo='ana@test.com' AND fhasta=${VIGENTE}`))[0];
    check('persona en TPERSONAS: CPERSONA ≥ 2 (el 1 es el administrador), correo en minúsculas, documento 001', persona && Number(persona.cpersona) >= 2 && persona.ctipodocumento === '001' && persona.fcorreoverificado);
    fila = (await q('SELECT * FROM vusuarios WHERE email=$1', ['ana@test.com']))[0];
    check('la BD genera el usuario a partir del nombre: aperez, rol 001, activo', fila && fila.usuario === 'aperez' && fila.rol === '001' && fila.activo === true, JSON.stringify(fila && fila.usuario));
    check('clave con bcrypt y términos aceptados (versión 1.0)', fila.clavehash.startsWith('$2') && !!fila.terminosen && fila.terminosver === '1.0');
    const tel = (await q(`SELECT * FROM tpersonatelefonos WHERE cpersona=$1 AND fhasta=${VIGENTE}`, [persona.cpersona]))[0];
    check('teléfono guardado como principal (STELEFONO=1)', tel && tel.numerotelefono === '0991000001' && tel.esprincipal === true && tel.stelefono === 1);
    check('se creó la fila de acceso (TUSUARIOSACCESO)', (await q("SELECT 1 FROM tusuariosacceso WHERE cusuario='aperez'")).length === 1);
    r = await api('POST', '/api/auth/register', { nombre: 'Ana', apellido: 'Pérez', email: 'ana@test.com', telefono: '0991000009', cedula: cedula(17, 1002), password: 'secreto1', tipoUsuario: 'cliente' });
    check('el código de verificación no sirve dos veces: 403', r.status === 403 && r.body.code === 'EMAILNOVERIFICADO');
    r = await api('POST', '/api/auth/send-verification', { email: 'ana@test.com' });
    check('no se envían códigos a un email ya registrado: 409', r.status === 409 && r.body.code === 'EMAILDUPLICADO');
    r = await api('GET', '/api/auth/check-email/ANA@test.com');
    check('check-email normaliza mayúsculas: exists=true', r.body.exists === true);

    seccion('6. Duplicados, roles y usuarios generados');
    await verificar('luis@test.com', 'Luis');
    r = await api('POST', '/api/auth/register', { nombre: 'Luis', apellido: 'Mora', email: 'luis@test.com', telefono: '0991000002', cedula: cedula(17, 1003), password: 'secreto1', tipoUsuario: 'vendedor' });
    check('vendedor: 201 con rol 002', r.status === 201 && r.body.usuario.tipoUsuario === 'vendedor' && r.body.usuario.usuario === 'lmora', JSON.stringify(r.body));
    await verificar('hack@test.com', 'Hack');
    r = await api('POST', '/api/auth/register', { nombre: 'Hack', apellido: 'Er', email: 'hack@test.com', telefono: '0991000005', cedula: cedula(17, 1006), password: 'secreto1', tipoUsuario: 'administrador' });
    check('registrarse como administrador: 400', r.status === 400 && /Tipo de usuario inválido/.test(r.body.error), JSON.stringify(r.body));
    r = await api('POST', '/api/auth/register', { nombre: 'Hack', apellido: 'Er', email: 'hack@test.com', telefono: '0991000001', cedula: cedula(17, 1006), password: 'secreto1', tipoUsuario: 'cliente' });
    check('teléfono ya usado: 409 y la verificación NO se gasta', r.status === 409 && r.body.code === 'TELEFONODUPLICADO', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/register', { nombre: 'Hack', apellido: 'Er', email: 'hack@test.com', telefono: '0991000005', cedula: cedula(17, 1001), password: 'secreto1', tipoUsuario: 'cliente' });
    check('cédula ya usada: 409', r.status === 409 && r.body.code === 'CEDULADUPLICADA', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/register', { nombre: 'Hack', apellido: 'Er', email: 'hack@test.com', telefono: '0991000005', cedula: cedula(17, 1006), password: 'secreto1', tipoUsuario: 'cliente' });
    check('tras los 409 la verificación sigue vigente (rollback): registra OK', r.status === 201, JSON.stringify(r.body));
    r = await registrarCliente('ana2@test.com', 'Ana', 'Pérez');
    check('homónima: aperez ocupado -> aperez2', r.status === 201 && r.body.usuario.usuario === 'aperez2', JSON.stringify(r.body.usuario || r.body));
    r = await registrarCliente('jandry@test.com', 'Jandry Franklin', 'Cayapa Baque');
    check('"Jandry Franklin Cayapa Baque" -> jcayapa', r.status === 201 && r.body.usuario.usuario === 'jcayapa', JSON.stringify(r.body.usuario || r.body));
    r = await registrarCliente('juan@test.com', 'Juan Fernando', 'Cayapa Bravo');
    check('otro "J. F. Cayapa": jcayapa ocupado -> jfcayapa', r.status === 201 && r.body.usuario.usuario === 'jfcayapa', JSON.stringify(r.body.usuario || r.body));
    r = await registrarCliente('maria@test.com', 'María del Carmen', 'De la Torre');
    check('partículas ignoradas (del, de, la): mtorre', r.status === 201 && r.body.usuario.usuario === 'mtorre', JSON.stringify(r.body.usuario || r.body));
    const ids = (await q('SELECT cpersona FROM tpersonas WHERE fhasta=$1 ORDER BY cpersona'.replace('$1', VIGENTE))).map((x) => Number(x.cpersona));
    check('CPERSONA: el 1 es el administrador y los demás van en orden creciente desde el 2', ids[0] === 1 && ids.slice(1).every((v, i) => v >= 2 && (i === 0 || v > ids[i])), JSON.stringify(ids));

    seccion('7. Login, bloqueo por intentos y token de acceso');
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'mala' });
    check('clave incorrecta: 401 genérico', r.status === 401 && r.body.error === 'Credenciales inválidas');
    r = await api('POST', '/api/auth/login', { email: 'noexiste@test.com', password: 'mala' });
    check('usuario inexistente: el mismo 401 (no revela si existe)', r.status === 401 && r.body.error === 'Credenciales inválidas');
    r = await api('POST', '/api/auth/login', { email: 'ANA@test.com', password: 'secreto1', dispositivo: 'Pixel 7', plataforma: 'android' });
    check('login con email en mayúsculas: 200 + token + refreshToken', r.status === 200 && !!r.body.token && !!r.body.refreshToken && r.body.usuario.tipoUsuario === 'cliente');
    const loginAna = r.body;
    const payload = JSON.parse(Buffer.from(loginAna.token.split('.')[1], 'base64url').toString());
    check('el token de acceso dura 15 minutos y no lleva cédula', payload.exp - payload.iat === 900 && payload.id === 'aperez' && payload.cedula === undefined, JSON.stringify(payload));
    fila = (await q("SELECT * FROM vusuarios WHERE usuario='aperez'"))[0];
    check('el login actualiza ULTIMACONEXION y reinicia intentos', !!fila.ultimaconexion && fila.intentosfallidos === 0);
    check('los logins NO crean versiones: TUSUARIOS sigue con 1 sola fila', (await q("SELECT 1 FROM tusuarios WHERE cusuario='aperez'")).length === 1);
    r = await api('POST', '/api/auth/login', { usuario: 'APEREZ', password: 'secreto1' });
    check('también con el usuario (campo "usuario", en mayúsculas): 200', r.status === 200 && r.body.usuario.email === 'ana@test.com');
    r = await api('POST', '/api/auth/login', { email: 'a b', password: 'x' });
    check('formato inválido: 400 "Escribe tu correo o tu usuario"', r.status === 400 && /correo o tu usuario/.test(r.body.error));
    r = await api('GET', '/api/auth/profile', null, loginAna.token);
    check('perfil con token: 200', r.status === 200 && r.body.usuario.email === 'ana@test.com' && r.body.usuario.fotoPerfil === null);
    r = await api('GET', '/api/auth/profile');
    check('perfil sin token: 401 TOKENNOPROPORCIONADO', r.status === 401 && r.body.code === 'TOKENNOPROPORCIONADO');
    r = await api('GET', '/api/auth/profile', null, 'basura.token.falso');
    check('token falso: 401 "Token inválido"', r.status === 401 && r.body.error === 'Token inválido');
    for (let i = 1; i <= 5; i++) r = await api('POST', '/api/auth/login', { email: 'luis@test.com', password: 'mala' });
    r = await api('POST', '/api/auth/login', { email: 'luis@test.com', password: 'secreto1' });
    check('5 fallos: aun con la clave CORRECTA, 429 CUENTABLOQUEADA con retryAfter', r.status === 429 && r.body.code === 'CUENTABLOQUEADA' && r.body.retryAfter > 0, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    check('otra cuenta no se ve afectada', r.status === 200);
    r = await api('POST', '/api/auth/login', { email: 'admin', password: 'cualquiera' });
    check('el administrador sembrado no puede entrar mientras no tenga clave real', r.status === 401);

    seccion('8. Sesión persistente: renovar con el refresh token');
    const sesiones = await q("SELECT * FROM tsesiones WHERE cusuario='aperez' ORDER BY ssesion");
    const primera = sesiones.find((s) => s.tokenhash === sha256(loginAna.refreshToken));
    check('en TSESIONES se guarda el HASH (SHA-256) del refresh token, nunca el token', !!primera && primera.tokenhash.length === 64 && !JSON.stringify(sesiones).includes(loginAna.refreshToken));
    check('la sesión guarda dispositivo y plataforma, y vence a los 90 días', primera.dispositivo === 'Pixel 7' && primera.plataforma === 'ANDROID' && Math.round((new Date(primera.fexpira) - Date.now()) / 86400000) === 90);

    const vencido = jwt.sign({ id: 'aperez', tipoUsuario: 'cliente' }, process.env.JWT_SECRET, { expiresIn: -10 });
    r = await api('GET', '/api/auth/profile', null, vencido);
    check('token de acceso vencido: 401 TOKENEXPIRADO (la app debe renovarlo)', r.status === 401 && r.body.code === 'TOKENEXPIRADO');

    r = await api('POST', '/api/auth/refresh', {});
    check('refresh sin token: 400', r.status === 400);
    r = await api('POST', '/api/auth/refresh', { refreshToken: 'x'.repeat(48) });
    check('refresh con token desconocido: 401 REFRESHINVALIDO', r.status === 401 && r.body.code === 'REFRESHINVALIDO');

    r = await api('POST', '/api/auth/refresh', { refreshToken: loginAna.refreshToken });
    check('refresh correcto: 200 con token de acceso nuevo y refresh token NUEVO', r.status === 200 && !!r.body.token && !!r.body.refreshToken && r.body.refreshToken !== loginAna.refreshToken && r.body.usuario.id === 'aperez', JSON.stringify(r.body).slice(0, 160));
    const rotado = r.body;
    r = await api('GET', '/api/auth/profile', null, rotado.token);
    check('el token de acceso renovado funciona', r.status === 200);
    const familia = (await q("SELECT cfamilia, count(*)::int n FROM tsesiones WHERE cusuario='aperez' AND tokenhash = ANY($1) GROUP BY cfamilia", [[sha256(loginAna.refreshToken), sha256(rotado.refreshToken)]]));
    check('el token nuevo conserva la FAMILIA del anterior (mismo equipo) y el viejo queda marcado como usado', familia.length === 1 && familia[0].n === 2 && !!(await q('SELECT 1 FROM tsesiones WHERE tokenhash=$1 AND fusado IS NOT NULL', [sha256(loginAna.refreshToken)])).length);

    r = await api('POST', '/api/auth/refresh', { refreshToken: loginAna.refreshToken });
    check('reintento inmediato con el token viejo (red lenta): 409 REFRESHENUSO, sin revocar nada', r.status === 409 && r.body.code === 'REFRESHENUSO', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/refresh', { refreshToken: rotado.refreshToken });
    check('...y la sesión nueva sigue viva', r.status === 200);
    const rotado2 = r.body;

    await q("UPDATE tsesiones SET fusado = now() - interval '1 minute' WHERE tokenhash=$1", [sha256(loginAna.refreshToken)]);
    r = await api('POST', '/api/auth/refresh', { refreshToken: loginAna.refreshToken });
    check('reutilizar un token ya canjeado (posible robo): 401 REFRESHREUTILIZADO', r.status === 401 && r.body.code === 'REFRESHREUTILIZADO', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/refresh', { refreshToken: rotado2.refreshToken });
    check('...y se revoca TODA la familia: el token legítimo también deja de servir (SESIONCERRADA)', r.status === 401 && r.body.code === 'SESIONCERRADA', JSON.stringify(r.body));
    check('motivo de revocación REUSO guardado', (await q("SELECT 1 FROM tsesiones WHERE motivorevocacion='REUSO' AND cusuario='aperez'")).length >= 2);

    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1', dispositivo: 'iPhone', plataforma: 'ios' });
    const sesB = r.body;
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1', dispositivo: 'Navegador', plataforma: 'web' });
    const sesC = r.body;
    r = await api('POST', '/api/auth/logout', { refreshToken: sesB.refreshToken });
    check('logout: 200', r.status === 200);
    r = await api('POST', '/api/auth/refresh', { refreshToken: sesB.refreshToken });
    check('tras cerrar sesión el refresh token ya no sirve: 401 SESIONCERRADA', r.status === 401 && r.body.code === 'SESIONCERRADA');
    r = await api('POST', '/api/auth/logout', { refreshToken: sesB.refreshToken });
    check('cerrar sesión dos veces no es un error', r.status === 200);
    r = await api('POST', '/api/auth/refresh', { refreshToken: sesC.refreshToken });
    check('las otras sesiones de la persona siguen vivas', r.status === 200);
    const sesC2 = r.body;
    r = await api('POST', '/api/auth/logout-all', {}, sesC2.token);
    check('logout-all (autenticado): 200 con la cantidad cerrada', r.status === 200 && r.body.cerradas >= 1, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/refresh', { refreshToken: sesC2.refreshToken });
    check('después de logout-all ninguna sesión renueva', r.status === 401);
    r = await api('POST', '/api/auth/logout-all', {});
    check('logout-all sin token de acceso: 401', r.status === 401);

    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    const sesD = r.body;
    await q("UPDATE tsesiones SET fexpira = now() - interval '1 hour' WHERE tokenhash=$1", [sha256(sesD.refreshToken)]);
    r = await api('POST', '/api/auth/refresh', { refreshToken: sesD.refreshToken });
    check('sesión de más de 90 días sin usar: 401 REFRESHEXPIRADO', r.status === 401 && r.body.code === 'REFRESHEXPIRADO');

    seccion('9. Cuenta desactivada');
    r = await api('POST', '/api/auth/login', { email: 'ana2@test.com', password: 'secreto1' });
    const sesE = r.body;
    await q("UPDATE tusuarios SET cestatususuario='002' WHERE cusuario='aperez2'");
    r = await api('GET', '/api/auth/profile', null, sesE.token);
    check('usuario desactivado: su token de acceso deja de servir (403)', r.status === 403 && r.body.code === 'CUENTADESACTIVADA');
    r = await api('POST', '/api/auth/refresh', { refreshToken: sesE.refreshToken });
    check('...y no puede renovar la sesión (403) ni iniciar sesión', r.status === 403 && r.body.code === 'CUENTADESACTIVADA');
    r = await api('POST', '/api/auth/login', { email: 'ana2@test.com', password: 'secreto1' });
    check('login de cuenta desactivada: 403', r.status === 403);
    const hv = await q("SELECT versioncontrol, cestatususuario, fhasta FROM tusuarios WHERE cusuario='aperez2' ORDER BY fdesde");
    check('el cambio de estatus quedó en el historial (2 versiones: 001 cerrada y 002 vigente)', hv.length === 2 && hv[0].cestatususuario === '001' && hv[1].cestatususuario === '002' && hv[1].versioncontrol === 1, JSON.stringify(hv));

    seccion('10. Cambiar clave autenticado');
    r = await api('POST', '/api/auth/login', { email: 'jandry@test.com', password: 'secreto1' });
    const jA = r.body;
    r = await api('POST', '/api/auth/login', { email: 'jandry@test.com', password: 'secreto1' });
    const jB = r.body;
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'incorrecta', passwordNueva: 'nuevaClave1' }, jA.token);
    check('clave actual incorrecta: 401', r.status === 401 && r.body.code === 'CLAVEACTUALINCORRECTA');
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'secreto1', passwordNueva: 'abc' }, jA.token);
    check('clave nueva muy corta: 400', r.status === 400);
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'secreto1', passwordNueva: 'nuevaClave1' }, jA.token);
    check('cambio correcto: 200 y devuelve una SESIÓN NUEVA para este equipo', r.status === 200 && !!r.body.token && !!r.body.refreshToken, JSON.stringify(r.body).slice(0, 120));
    const jNueva = r.body;
    r = await api('POST', '/api/auth/refresh', { refreshToken: jB.refreshToken });
    check('las sesiones de los OTROS equipos se cierran: 401 SESIONCERRADA', r.status === 401 && r.body.code === 'SESIONCERRADA');
    r = await api('POST', '/api/auth/refresh', { refreshToken: jA.refreshToken });
    check('la sesión vieja de este mismo equipo también se cierra', r.status === 401);
    r = await api('POST', '/api/auth/refresh', { refreshToken: jNueva.refreshToken });
    check('la sesión nueva entregada al cambiar la clave SÍ renueva', r.status === 200);
    r = await api('POST', '/api/auth/login', { email: 'jandry@test.com', password: 'nuevaClave1' });
    check('login con la clave nueva: 200', r.status === 200);
    const hc = await q("SELECT versioncontrol v, fhasta, cusuario_modificacion m FROM tusuarios WHERE cusuario='jcayapa' ORDER BY fdesde");
    check('el cambio de clave SÍ versiona: v0 cerrada y v1 vigente (2999), y registra quién lo hizo', hc.length === 2 && hc[0].v === 0 && hc[1].v === 1 && new Date(hc[1].fhasta).getUTCFullYear() === 2999 && hc[1].m === 'jcayapa', JSON.stringify(hc));

    seccion('11. Recuperar contraseña');
    r = await api('POST', '/api/auth/forgot-password', { email: 'noexiste@test.com' });
    check('correo inexistente: mismo 200 (no revela si existe)', r.status === 200 && /Si el correo existe/.test(r.body.message));
    desde = t.marca();
    r = await api('POST', '/api/auth/forgot-password', { email: 'juan@test.com' });
    check('correo existente: 200', r.status === 200);
    const codReset = await t.codigoDe('juan@test.com', 'reset', desde);
    check('se generó un código de 6 dígitos', /^\d{6}$/.test(codReset || ''));
    r = await api('POST', '/api/auth/login', { email: 'juan@test.com', password: 'secreto1' });
    const sesJuan = r.body;
    r = await api('POST', '/api/auth/verify-reset-code', { email: 'juan@test.com', code: codReset });
    check('verificar el código: 200 con resetToken', r.status === 200 && !!r.body.resetToken, JSON.stringify(r.body));
    const resetToken = r.body.resetToken;
    r = await api('POST', '/api/auth/reset-password', { resetToken, newPassword: 'claveNueva9' });
    check('restablecer: 200', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/reset-password', { resetToken, newPassword: 'otraClave99' });
    check('el resetToken es de UN solo uso: 401 TOKENRESETUSADO', r.status === 401 && r.body.code === 'TOKENRESETUSADO', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'juan@test.com', password: 'claveNueva9' });
    check('login con la clave restablecida: 200', r.status === 200);
    r = await api('POST', '/api/auth/refresh', { refreshToken: sesJuan.refreshToken });
    check('restablecer la clave cierra las sesiones que había (quien la robó pierde acceso)', r.status === 401 && r.body.code === 'SESIONCERRADA');

    seccion('12. Perfil');
    r = await api('POST', '/api/auth/login', { email: 'maria@test.com', password: 'secreto1' });
    const mar = r.body;
    r = await api('PUT', '/api/auth/profile', { nombre: 'Mariana', telefono: '0997770000' }, mar.token);
    check('actualizar nombre y teléfono: 200', r.status === 200 && r.body.usuario.nombre === 'Mariana' && r.body.usuario.telefono === '0997770000', JSON.stringify(r.body).slice(0, 160));
    const hp = await q(`SELECT nombres, versioncontrol v, cusuario_modificacion m, fhasta FROM tpersonas WHERE cpersona=(SELECT cpersona FROM vusuarios WHERE usuario='mtorre') ORDER BY fdesde`);
    check('TPERSONAS versiona el cambio (María -> Mariana) y registra quién lo hizo (mtorre)', hp.length === 2 && hp[0].nombres === 'María del Carmen' && hp[1].nombres === 'Mariana' && hp[1].m === 'mtorre', JSON.stringify(hp));
    const ht = await q(`SELECT numerotelefono, fhasta FROM tpersonatelefonos WHERE cpersona=(SELECT cpersona FROM vusuarios WHERE usuario='mtorre') ORDER BY fdesde`);
    check('el teléfono también versiona: queda el anterior cerrado y el nuevo vigente', ht.length === 2 && ht[1].numerotelefono === '0997770000');
    r = await api('PUT', '/api/auth/profile', { telefono: '0991000001' }, mar.token);
    check('teléfono de otra persona: 409 TELEFONODUPLICADO', r.status === 409 && r.body.code === 'TELEFONODUPLICADO', JSON.stringify(r.body));
    r = await api('PUT', '/api/auth/profile', { nombre: '' }, mar.token);
    check('nombre vacío: 400', r.status === 400);
    r = await api('GET', '/api/usuarios/perfil', null, mar.token);
    check('GET /api/usuarios/perfil: formato { success, data }', r.status === 200 && r.body.success === true && r.body.data.id === 'mtorre');
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: 'abc' }, mar.token);
    check('la foto de perfil aún no está disponible: 501 NOIMPLEMENTADO', r.status === 501 && r.body.code === 'NOIMPLEMENTADO');
    r = await api('POST', '/api/usuarios/cambiar-contrasena', { passwordActual: 'secreto1', passwordNueva: 'otraNueva1', confirmarPassword: 'distinta' }, mar.token);
    check('confirmación distinta: 400', r.status === 400);

    seccion('13. Auditoría y logs');
    const acciones = (await q('SELECT DISTINCT accion FROM tauditoria')).map((x) => x.accion);
    check('TAUDITORIA registra REGISTRO, LOGIN, LOGINFALLIDO, LOGOUT, CAMBIOCLAVE y RESETCLAVE', ['REGISTRO', 'LOGIN', 'LOGINFALLIDO', 'LOGOUT', 'CAMBIOCLAVE', 'RESETCLAVE'].every((a) => acciones.includes(a)), acciones.join(','));
    const secretos = await q("SELECT count(*)::int n FROM tauditoria WHERE detalle::text ~* 'secreto1|nuevaClave1|\\$2[aby]\\$'");
    check('la auditoría no guarda claves ni hashes', secretos[0].n === 0);
    check('TLOGMENSAJES registra el reuso de refresh token', (await q("SELECT 1 FROM tlogmensajes WHERE accion='REFRESHREUTILIZADO'")).length >= 1);

    seccion('14. Base de datos');
    check('el administrador (CPERSONA 1) sigue intacto', (await q(`SELECT 1 FROM tpersonas WHERE cpersona=1 AND fhasta=${VIGENTE}`)).length === 1);
    const mayus = (await q("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='public' AND (column_name<>lower(column_name) OR table_name<>lower(table_name))"))[0].n;
    const uuidsCol = (await q("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='public' AND data_type='uuid' AND table_name<>'tsesiones'"))[0].n;
    check('ningún nombre guardado con mayúsculas y UUID solo en la familia de sesiones', mayus === 0 && uuidsCol === 0, `mayus=${mayus} uuid=${uuidsCol}`);
    const purga = (await q('SELECT * FROM purgarsesiones()'))[0];
    check('PURGARSESIONES() corre sin errores', purga && purga.sesiones >= 0);
    await t.finalizar();
  } catch (e) {
    await t.finalizar(e);
  }
})();
