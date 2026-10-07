// Prueba de extremo a extremo del módulo auth.  Uso:  npm run test:auth   (desde la carpeta backend)
//
// Crea su PROPIA base temporal "vallexpress_test" (con database/schema.sql), levanta el servidor contra ella,
// recorre el flujo completo como lo haría la app (registro, login, recuperar clave, límites, logs...) y al
// terminar borra la base temporal. NO toca la base de desarrollo. Requiere Postgres en marcha (docker compose).
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const BACKEND = path.resolve(__dirname, '..');
require('dotenv').config({ path: path.join(BACKEND, '.env') });
const { Client } = require('pg');
const PUERTO = 3099;
const BASE = `http://localhost:${PUERTO}`;

let ok = 0; const fallos = [];
const check = (nombre, cond, detalle = '') => {
  if (cond) { ok++; console.log(`  ✔ ${nombre}`); } else { fallos.push(nombre); console.log(`  ✘ ${nombre}  ${detalle}`); }
};
const seccion = (t) => console.log(`\n── ${t}`);
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(metodo, ruta, cuerpo, token) {
  const r = await fetch(BASE + ruta, {
    method: metodo,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  let json = null; try { json = await r.json(); } catch { /* sin cuerpo */ }
  return { status: r.status, body: json, headers: r.headers };
}

// Cédulas ecuatorianas válidas (mismo algoritmo módulo 10 del backend)
function cedula(prov, n) {
  const d = (String(prov).padStart(2, '0') + String(n).padStart(7, '0')).split('').map(Number);
  let s = 0; for (let i = 0; i < 9; i++) { const m = d[i] * (i % 2 === 0 ? 2 : 1); s += m > 9 ? m - 9 : m; }
  return d.join('') + ((10 - (s % 10)) % 10);
}

// Captura de la consola del servidor (los códigos se imprimen en desarrollo cuando no hay proveedor de correo)
let salida = '';
async function codigoDe(tipo, email, desde = 0) {
  const re = new RegExp(`\\[DEV\\] Código de ${tipo} para ${email.replace(/[.+]/g, '\\$&')}: (\\d{6})`, 'g');
  for (let i = 0; i < 40; i++) {
    const m = [...salida.slice(desde).matchAll(re)].pop();
    if (m) return m[1];
    await dormir(100);
  }
  return null;
}

async function verificarEmail(email, nombre = 'Test') {
  const marca = salida.length;
  const env = await api('POST', '/api/auth/send-verification', { email, nombre });
  if (env.status !== 200) return { env };
  const code = await codigoDe('verificacion', email.toLowerCase(), marca);
  const ver = await api('POST', '/api/auth/verify-email', { email, code });
  return { env, code, ver };
}

const dbConfig = (database) => ({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD, database });

async function prepararBaseTemporal() {
  const admin = new Client(dbConfig('postgres'));
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS vallexpress_test WITH (FORCE)');
  await admin.query('CREATE DATABASE vallexpress_test');
  await admin.end();
  const temp = new Client(dbConfig('vallexpress_test'));
  await temp.connect();
  await temp.query(fs.readFileSync(path.join(BACKEND, '..', 'database', 'schema.sql'), 'utf8'));
  await temp.end();
}
async function borrarBaseTemporal() {
  const admin = new Client(dbConfig('postgres'));
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS vallexpress_test WITH (FORCE)');
  await admin.end();
}

(async () => {
  await prepararBaseTemporal();
  let srv = spawn(process.execPath, ['src/server.js'], {
    cwd: BACKEND,
    env: { ...process.env, NODE_ENV: 'development', PORT: String(PUERTO), DB_NAME: 'vallexpress_test', LIMITES_DESACTIVADOS: 'true' },
  });
  srv.stdout.on('data', (d) => { salida += d.toString(); });
  srv.stderr.on('data', (d) => { salida += d.toString(); });

  const db = new Client(dbConfig('vallexpress_test'));
  try {
    for (let i = 0; i < 50; i++) { try { if ((await fetch(`${BASE}/api/health`)).ok) break; } catch { /* aún no */ } await dormir(200); }
    await db.connect();
    const q = async (sql, p) => (await db.query(sql, p)).rows;

    seccion('1. Servidor y formato de respuestas');
    const h = await api('GET', '/api/health');
    check('health responde 200', h.status === 200);
    check('cada petición lleva X-Request-Id', /^[\w-]{8,64}$/.test(h.headers.get('x-request-id') || ''));
    const nf = await api('GET', '/api/no-existe');
    check('ruta inexistente: 404 con "error" en texto', nf.status === 404 && typeof nf.body.error === 'string' && nf.body.code === 'RUTANOENCONTRADA', JSON.stringify(nf.body));

    seccion('2. Validación y consultas en tiempo real');
    let r = await api('GET', `/api/auth/check-cedula/${cedula(17, 1)}`);
    check('cédula libre', r.status === 200 && r.body.exists === false);
    r = await api('GET', '/api/auth/check-cedula/1234567890');
    check('cédula inválida: 400 con mensaje claro', r.status === 400 && /Cédula inválida/.test(r.body.error), JSON.stringify(r.body));
    r = await api('GET', '/api/auth/check-placa/ZZ99');
    check('placa inválida: 400', r.status === 400);
    r = await api('POST', '/api/auth/register', { nombre: 'A', apellido: 'B', email: 'malo', telefono: '123', cedula: '1', password: '12', tipoUsuario: 'cliente' });
    check('registro inválido: 400, primer mensaje en "error" y lista en "errors"', r.status === 400 && typeof r.body.error === 'string' && Array.isArray(r.body.errors) && r.body.errors.length >= 3, JSON.stringify(r.body).slice(0, 200));

    seccion('3. Registro exige email verificado (en el servidor)');
    const ced1 = cedula(17, 1001); const tel1 = '0991000001';
    r = await api('POST', '/api/auth/register', { nombre: 'Ana', apellido: 'Pérez', email: 'Ana@Test.com', telefono: tel1, cedula: ced1, password: 'secreto1', tipoUsuario: 'cliente' });
    check('sin verificar email: 403 EMAILNOVERIFICADO', r.status === 403 && r.body.code === 'EMAILNOVERIFICADO', JSON.stringify(r.body));

    seccion('4. Verificación de email');
    let marca = salida.length;
    r = await api('POST', '/api/auth/send-verification', { email: 'Ana@Test.com', nombre: 'Ana' });
    check('enviar código: 200', r.status === 200, JSON.stringify(r.body));
    const codAna = await codigoDe('verificacion', 'ana@test.com', marca);
    check('el código es de 6 dígitos y se generó para el email normalizado (minúsculas)', /^\d{6}$/.test(codAna || ''));
    r = await api('POST', '/api/auth/send-verification', { email: 'ana@test.com' });
    check('reenvío inmediato: 429 con retryAfter (cooldown 60 s)', r.status === 429 && r.body.retryAfter > 0, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/verify-email', { email: 'ana@test.com', code: codAna === '000000' ? '111111' : '000000' });
    check('código incorrecto: 400', r.status === 400 && r.body.code === 'CODIGOINCORRECTO');
    r = await api('POST', '/api/auth/verify-email', { email: 'ana@test.com', code: '12' });
    check('código mal formado: 400 "debe tener 6 dígitos"', r.status === 400 && /6 dígitos/.test(r.body.error));
    r = await api('POST', '/api/auth/verify-email', { email: 'ana@test.com', code: codAna });
    check('código correcto: verified=true', r.status === 200 && r.body.verified === true, JSON.stringify(r.body));

    seccion('5. Registro de cliente');
    r = await api('POST', '/api/auth/register', { nombre: 'Ana', apellido: 'Pérez', email: 'Ana@Test.com', telefono: tel1, cedula: ced1, password: 'secreto1', tipoUsuario: 'cliente' });
    check('registro: 201', r.status === 201, JSON.stringify(r.body));
    const tokenAna = r.body?.token;
    check('devuelve token y usuario con el formato de la app', !!tokenAna && r.body.usuario?.tipoUsuario === 'cliente' && r.body.usuario?.verificado === true && r.body.usuario?.cedula === ced1);
    check('NO devuelve el hash de la clave', !JSON.stringify(r.body).includes('passwordHash') && !JSON.stringify(r.body).includes('$2'));
    let fila = (await q('SELECT * FROM usuarios WHERE email=$1', ['ana@test.com']))[0];
    check('en la BD: email en minúsculas, ROL=001 y la CLAVE PRIMARIA es el usuario (aperez)', fila && fila.rol === '001' && fila.usuario === 'aperez' && fila.email === 'ana@test.com', JSON.stringify(fila && { r: fila.rol, u: fila.usuario }));
    check('en la BD: clave con bcrypt y términos registrados', fila.clavehash.startsWith('$2') && !!fila.terminosen && fila.terminosver === '1.0');
    check('se registra a sí mismo como creador: CREADOPOR = su usuario', fila.creadopor === fila.usuario);
    r = await api('POST', '/api/auth/register', { nombre: 'Ana', apellido: 'Pérez', email: 'ana@test.com', telefono: '0991000009', cedula: cedula(17, 1002), password: 'secreto1', tipoUsuario: 'cliente' });
    check('el código de verificación no sirve dos veces: 403', r.status === 403 && r.body.code === 'EMAILNOVERIFICADO', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/send-verification', { email: 'ana@test.com' });
    check('no se envían códigos a un email ya registrado: 409', r.status === 409 && r.body.code === 'EMAILDUPLICADO');
    r = await api('GET', '/api/auth/check-email/ANA@test.com');
    check('check-email normaliza mayúsculas: exists=true', r.body.exists === true);

    seccion('6. Registro de vendedor y repartidor (con duplicados y escalada de rol)');
    const v = await verificarEmail('luis@test.com');
    check('verificar email de vendedor', v.ver?.body?.verified === true);
    r = await api('POST', '/api/auth/register', { nombre: 'Luis', apellido: 'Mora', email: 'luis@test.com', telefono: '0991000002', cedula: cedula(17, 1003), password: 'secreto1', tipoUsuario: 'vendedor', nombreNegocio: 'Pizzería Luis' });
    check('vendedor: 201', r.status === 201, JSON.stringify(r.body));
    const ven = (await q('SELECT v.* FROM vendedores v JOIN usuarios u ON u.usuario=v.usuario WHERE u.email=$1', ['luis@test.com']))[0];
    check('fila en VENDEDORES: clave VEN-000001, relacionada por el CÓDIGO del usuario (lmora), negocio, categoría OTROS (099), aprobado (002)', ven && /^VEN-\d{6}$/.test(ven.vendedor) && ven.usuario === 'lmora' && ven.negocio === 'Pizzería Luis' && ven.categoria === '099' && ven.aprobacion === '002', JSON.stringify(ven && { v: ven.vendedor, u: ven.usuario }));

    const rp = await verificarEmail('pedro@test.com');
    check('verificar email de repartidor', rp.ver?.body?.verified === true);
    r = await api('POST', '/api/auth/register', { nombre: 'Pedro', apellido: 'Ruiz', email: 'pedro@test.com', telefono: '0991000003', cedula: cedula(17, 1004), password: 'secreto1', tipoUsuario: 'repartidor', vehiculo: 'Moto', placa: 'abc-123' });
    check('repartidor SIN licencia: 201 (antes fallaba siempre)', r.status === 201, JSON.stringify(r.body));
    const rep = (await q('SELECT * FROM repartidores ORDER BY creadoen DESC LIMIT 1'))[0];
    check('REPARTIDORES: VEHICULO=001 (moto), PLACA=ABC123 normalizada, licencia nula, aprobado', rep && rep.vehiculo === '001' && rep.placa === 'ABC123' && rep.licencia === null && rep.aprobacion === '002', JSON.stringify(rep && { v: rep.vehiculo, p: rep.placa }));

    const rp2 = await verificarEmail('maria@test.com');
    r = await api('POST', '/api/auth/register', { nombre: 'Maria', apellido: 'Paz', email: 'maria@test.com', telefono: '0991000004', cedula: cedula(17, 1005), password: 'secreto1', tipoUsuario: 'repartidor', vehiculo: 'Patineta rara', placa: 'ABC-123' });
    check('placa repetida: 409', r.status === 409 && r.body.code === 'PLACADUPLICADA', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/register', { nombre: 'Maria', apellido: 'Paz', email: 'maria@test.com', telefono: '0991000004', cedula: cedula(17, 1005), password: 'secreto1', tipoUsuario: 'repartidor', vehiculo: 'Patineta rara', placa: 'XYZ-987' });
    check('tras el 409 la verificación NO se gastó (rollback): registra OK', r.status === 201, JSON.stringify(r.body));
    const rep2 = (await q('SELECT r.* FROM repartidores r JOIN usuarios u ON u.usuario=r.usuario WHERE u.email=$1', ['maria@test.com']))[0];
    check('vehículo de texto libre desconocido: VEHICULO nulo y el texto va a DATOSEXTRA', rep2 && rep2.vehiculo === null && /Patineta rara/.test(rep2.datosextra || ''), JSON.stringify(rep2 && { v: rep2.vehiculo, d: rep2.datosextra }));

    const rh = await verificarEmail('hack@test.com');
    r = await api('POST', '/api/auth/register', { nombre: 'Hack', apellido: 'Er', email: 'hack@test.com', telefono: '0991000005', cedula: cedula(17, 1006), password: 'secreto1', tipoUsuario: 'administrador' });
    check('registrarse como administrador: 400', r.status === 400 && /Tipo de usuario inválido/.test(r.body.error), JSON.stringify(r.body));
    r = await api('POST', '/api/auth/register', { nombre: 'Hack', apellido: 'Er', email: 'hack@test.com', telefono: '0991000001', cedula: cedula(17, 1006), password: 'secreto1', tipoUsuario: 'cliente' });
    check('teléfono ya usado: 409', r.status === 409 && r.body.code === 'TELEFONODUPLICADO', JSON.stringify(r.body));

    seccion('6b. Usuario para iniciar sesión (lo genera la BD a partir del nombre)');
    const us = Object.fromEntries((await q('SELECT email,usuario FROM usuarios')).map((x) => [x.email, x.usuario]));
    check('inicial + primer apellido: Ana Pérez=aperez, Luis Mora=lmora, Pedro Ruiz=pruiz, María Paz=mpaz', us['ana@test.com'] === 'aperez' && us['luis@test.com'] === 'lmora' && us['pedro@test.com'] === 'pruiz' && us['maria@test.com'] === 'mpaz', JSON.stringify(us));
    const reg = async (email, nombre, apellido, n) => {
      await verificarEmail(email);
      return api('POST', '/api/auth/register', { nombre, apellido, email, telefono: `09910001${String(n).padStart(2, '0')}`, cedula: cedula(17, 1100 + n), password: 'secreto1', tipoUsuario: 'cliente' });
    };
    r = await reg('andres@test.com', 'Andrés', 'Pérez Soto', 11);
    check('el registro DEVUELVE el usuario; "aperez" ya existe -> añade la inicial del 2.º apellido: aperezs', r.status === 201 && r.body.usuario.usuario === 'aperezs', JSON.stringify(r.body.usuario || r.body));
    r = await reg('ana2@test.com', 'Ana', 'Pérez', 12);
    check('homónima (mismo nombre y apellido): aperez2', r.status === 201 && r.body.usuario.usuario === 'aperez2', JSON.stringify(r.body.usuario || r.body));
    r = await reg('jandry@test.com', 'Jandry Franklin', 'Cayapa Baque', 13);
    check('"Jandry Franklin Cayapa Baque" -> jcayapa', r.status === 201 && r.body.usuario.usuario === 'jcayapa', JSON.stringify(r.body.usuario || r.body));
    r = await reg('juan@test.com', 'Juan Fernando', 'Cayapa Bravo', 14);
    check('otro "J. F. Cayapa": jcayapa ocupado -> usa las dos iniciales: jfcayapa', r.status === 201 && r.body.usuario.usuario === 'jfcayapa', JSON.stringify(r.body.usuario || r.body));
    r = await reg('maria2@test.com', 'María del Carmen', 'De la Torre', 15);
    check('partículas ignoradas (del, de, la): mtorre', r.status === 201 && r.body.usuario.usuario === 'mtorre', JSON.stringify(r.body.usuario || r.body));
    fila = (await q('SELECT fhasta,versioncontrol FROM usuarios WHERE email=$1', ['ana@test.com']))[0];
    check('FHASTA vigente = 2999-12-31 00:00:00 (hora de Ecuador) y VERSIONCONTROL 0', new Date(fila.fhasta).toISOString() === '2999-12-31T05:00:00.000Z' && fila.versioncontrol === 0, String(fila && fila.fhasta));

    seccion('6c. Claves legibles, sin UUID y nombres sin comillas');
    r = await api('POST', '/api/auth/login', { email: 'aperez', password: 'secreto1' });
    check('el JWT y la respuesta usan el usuario como id: id=aperez, usuario=aperez', r.status === 200 && r.body.usuario.id === 'aperez' && r.body.usuario.usuario === 'aperez');
    const payload = JSON.parse(Buffer.from(r.body.token.split('.')[1], 'base64url').toString());
    check('el token lleva id=aperez (ya no un UUID)', payload.id === 'aperez' && payload.tipoUsuario === 'cliente', JSON.stringify(payload));
    const cambio = await db.query("UPDATE usuarios SET usuario='otro' WHERE usuario='aperez'").then(() => 'permitido').catch((e) => e.message);
    check('la clave del usuario NO se puede cambiar nunca (la BD lo rechaza)', /no se puede cambiar/.test(cambio), cambio);
    const sinComillas = await db.query('SELECT count(*)::int n FROM USUARIOS').then((x) => x.rows[0].n).catch((e) => e.message);
    check('SELECT * FROM USUARIOS sin comillas funciona', typeof sinComillas === 'number' && sinComillas >= 4, String(sinComillas));
    const uuids = (await q("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='public' AND data_type='uuid'"))[0].n;
    const mayus = (await q("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='public' AND (column_name<>lower(column_name) OR table_name<>lower(table_name))"))[0].n;
    check('no existe ninguna columna UUID ni ningún nombre con mayúsculas guardadas', uuids === 0 && mayus === 0, `uuid=${uuids} mayúsculas=${mayus}`);
    const fk = (await q("SELECT count(*)::int n FROM information_schema.referential_constraints WHERE constraint_schema='public'"))[0].n;
    check('las relaciones por código están protegidas con claves foráneas (≥ 50)', fk >= 50, String(fk));

    seccion('7. Login, bloqueo por intentos y token');
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'mala' });
    check('clave incorrecta: 401 genérico', r.status === 401 && r.body.error === 'Credenciales inválidas');
    r = await api('POST', '/api/auth/login', { email: 'noexiste@test.com', password: 'mala' });
    check('usuario inexistente: el mismo 401 (no revela si existe)', r.status === 401 && r.body.error === 'Credenciales inválidas');
    r = await api('POST', '/api/auth/login', { email: 'ANA@test.com', password: 'secreto1' });
    check('login correcto con email en mayúsculas: 200 + token', r.status === 200 && !!r.body.token && r.body.usuario.tipoUsuario === 'cliente', JSON.stringify(r.body).slice(0, 150));
    const tk = r.body.token;
    fila = (await q('SELECT * FROM usuarios WHERE email=$1', ['ana@test.com']))[0];
    check('login actualiza ULTIMACONEXION y reinicia intentos', !!fila.ultimaconexion && fila.intentosfallidos === 0);
    const hist = await q('SELECT count(*)::int n FROM histusuarios WHERE email=$1', ['ana@test.com']);
    check('los logins NO llenan el historial de versiones (columnas volátiles)', hist[0].n === 0, `HIST=${hist[0].n}`);
    r = await api('GET', '/api/auth/profile', null, tk);
    check('perfil con token: 200', r.status === 200 && r.body.usuario.email === 'ana@test.com');
    r = await api('GET', '/api/auth/profile');
    check('perfil sin token: 401', r.status === 401 && r.body.code === 'TOKENNOPROPORCIONADO');
    r = await api('GET', '/api/auth/profile', null, 'basura.token.falso');
    check('token falso: 401 "Token inválido"', r.status === 401 && r.body.error === 'Token inválido');

    for (let i = 1; i <= 4; i++) await api('POST', '/api/auth/login', { email: 'luis@test.com', password: 'mala' });
    r = await api('POST', '/api/auth/login', { email: 'luis@test.com', password: 'mala' });
    check('5.º intento fallido: sigue 401', r.status === 401);
    r = await api('POST', '/api/auth/login', { email: 'luis@test.com', password: 'secreto1' });
    check('con la clave CORRECTA pero bloqueado: 429 CUENTABLOQUEADA', r.status === 429 && r.body.code === 'CUENTABLOQUEADA' && r.body.retryAfter > 0, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'secreto1' });
    check('otra cuenta no se ve afectada', r.status === 200);

    seccion('7b. Iniciar sesión con el usuario');
    r = await api('POST', '/api/auth/login', { email: 'aperez', password: 'secreto1' });
    check('usuario en el campo "email" (así lo envía la app, sin cambios): 200', r.status === 200 && r.body.usuario.usuario === 'aperez' && r.body.usuario.email === 'ana@test.com', JSON.stringify(r.body).slice(0, 160));
    r = await api('POST', '/api/auth/login', { usuario: 'APEREZ', password: 'secreto1' });
    check('campo "usuario" y en MAYÚSCULAS: 200', r.status === 200 && !!r.body.token);
    const tkU = r.body.token;
    r = await api('GET', '/api/auth/profile', null, tkU);
    check('el perfil incluye el usuario', r.status === 200 && r.body.usuario.usuario === 'aperez');
    r = await api('POST', '/api/auth/login', { usuario: 'aperez', password: 'mala' });
    check('usuario correcto + clave mala: 401 genérico', r.status === 401 && r.body.error === 'Credenciales inválidas');
    r = await api('POST', '/api/auth/login', { usuario: 'noexiste99', password: 'x' });
    check('usuario inexistente: el MISMO 401 (no revela si existe)', r.status === 401 && r.body.error === 'Credenciales inválidas');
    r = await api('POST', '/api/auth/login', { email: 'a b', password: 'x' });
    check('formato inválido (espacio): 400 "Escribe tu correo o tu usuario"', r.status === 400 && /correo o tu usuario/.test(r.body.error), JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'ab', password: 'x' });
    check('demasiado corto (2 letras): 400', r.status === 400);
    r = await api('POST', '/api/auth/login', { password: 'x' });
    check('sin correo ni usuario: 400', r.status === 400);

    seccion('8. Cambiar clave autenticado');
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'incorrecta', passwordNueva: 'nuevaClave1' }, tk);
    check('clave actual incorrecta: 401', r.status === 401 && r.body.code === 'CLAVEACTUALINCORRECTA');
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'secreto1', passwordNueva: 'abc' }, tk);
    check('clave nueva muy corta: 400', r.status === 400);
    r = await api('PUT', '/api/auth/change-password', { passwordActual: 'secreto1', passwordNueva: 'nuevaClave1' }, tk);
    check('cambio correcto: 200', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'nuevaClave1' });
    check('login con la clave nueva: 200', r.status === 200);
    const h2 = await q('SELECT versioncontrol v FROM histusuarios WHERE email=$1 ORDER BY histid', ['ana@test.com']);
    check('el cambio de clave SÍ versiona (HIST con la versión anterior)', h2.length === 1 && h2[0].v === 0, JSON.stringify(h2));

    seccion('9. Recuperar contraseña');
    marca = salida.length;
    r = await api('POST', '/api/auth/forgot-password', { email: 'nadie@test.com' });
    check('email desconocido: mismo 200 genérico', r.status === 200 && /Si el correo existe/.test(r.body.message));
    await dormir(600);
    check('...y NO se envía ningún correo a cuentas inexistentes', !/Código de reset para nadie@test.com/.test(salida.slice(marca)));
    marca = salida.length;
    r = await api('POST', '/api/auth/forgot-password', { email: 'ana@test.com' });
    check('email real: 200 genérico', r.status === 200 && /Si el correo existe/.test(r.body.message));
    const codReset = await codigoDe('reset', 'ana@test.com', marca);
    check('se generó el código de reseteo', /^\d{6}$/.test(codReset || ''));
    r = await api('POST', '/api/auth/verify-reset-code', { email: 'ana@test.com', code: codReset === '000000' ? '111111' : '000000' });
    check('código de reseteo incorrecto: 400', r.status === 400);
    r = await api('POST', '/api/auth/verify-reset-code', { email: 'ana@test.com', code: codReset });
    check('código correcto: devuelve resetToken', r.status === 200 && !!r.body.resetToken);
    const resetToken = r.body.resetToken;
    r = await api('POST', '/api/auth/verify-reset-code', { email: 'ana@test.com', code: codReset });
    check('el código no se puede reutilizar: 400', r.status === 400);
    r = await api('POST', '/api/auth/reset-password', { resetToken, newPassword: 'claveReset9' });
    check('reset con el token: 200', r.status === 200, JSON.stringify(r.body));
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'claveReset9' });
    check('login con la clave restablecida: 200', r.status === 200);
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'nuevaClave1' });
    check('la clave anterior ya no sirve: 401', r.status === 401);
    r = await api('POST', '/api/auth/reset-password', { resetToken, newPassword: 'otraClave77' });
    check('el MISMO resetToken no sirve dos veces: 401 TOKENRESETUSADO', r.status === 401 && r.body.code === 'TOKENRESETUSADO', JSON.stringify(r.body));
    r = await api('POST', '/api/auth/reset-password', { resetToken: 'falso', newPassword: 'otraClave77' });
    check('resetToken falso: 401', r.status === 401);

    seccion('10. /api/usuarios (perfil del usuario)');
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'claveReset9' });
    const tk2 = r.body.token;
    r = await api('GET', '/api/usuarios/perfil', null, tk2);
    check('GET perfil: { success, data }', r.status === 200 && r.body.success === true && r.body.data.email === 'ana@test.com');
    r = await api('PUT', '/api/usuarios/actualizar', { nombre: 'Ana María', telefono: '0997777777' }, tk2);
    check('actualizar perfil: 200', r.status === 200 && r.body.data.nombre === 'Ana María' && r.body.data.telefono === '0997777777', JSON.stringify(r.body));
    r = await api('PUT', '/api/usuarios/actualizar', { telefono: '0991000002' }, tk2);
    check('actualizar con teléfono de otro usuario: 409', r.status === 409);
    r = await api('POST', '/api/usuarios/cambiar-contrasena', { passwordActual: 'claveReset9', passwordNueva: 'otraClave88', confirmarPassword: 'distinta' }, tk2);
    check('confirmación distinta: 400 "no coinciden"', r.status === 400 && /no coinciden/.test(r.body.error), JSON.stringify(r.body));
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: 'abc' }, tk2);
    check('foto de perfil inválida: 400 (el servicio de imágenes ya está activo)', r.status === 400 && r.body.code === 'IMAGENINVALIDA');

    seccion('11. Límites de peticiones (segundo servidor, con los límites ENCENDIDOS)');
    srv.kill(); await dormir(800);
    srv = spawn(process.execPath, ['src/server.js'], { cwd: BACKEND, env: { ...process.env, NODE_ENV: 'development', PORT: String(PUERTO), DB_NAME: 'vallexpress_test' } });
    srv.stdout.on('data', (d) => { salida += d.toString(); }); srv.stderr.on('data', (d) => { salida += d.toString(); });
    for (let i = 0; i < 50; i++) { try { if ((await fetch(`${BASE}/api/health`)).ok) break; } catch { /* aún no */ } await dormir(200); }
    let n429 = 0; let primero = null; let r429;
    for (let i = 0; i < 45; i++) { const x = await api('GET', `/api/auth/check-email/limite${i}@test.com`); if (x.status === 429) { n429++; primero = primero ?? i + 1; r429 = x; } }
    check('consultas: del intento 41 en adelante responde 429', n429 === 5 && primero === 41, `429s=${n429}, primero=${primero}`);
    check('el 429 trae mensaje, código y retryAfter', r429 && typeof r429.body.error === 'string' && r429.body.code === 'LIMITEEXCEDIDO' && r429.body.retryAfter > 0, JSON.stringify(r429 && r429.body));
    let a = 0; for (let i = 0; i < 5; i++) { const x = await api('POST', '/api/auth/forgot-password', { email: `lim${i}@test.com` }); if (x.status === 200) a++; }
    const x6 = await api('POST', '/api/auth/forgot-password', { email: 'lim9@test.com' });
    check('recuperar clave: 5 por minuto y el 6.º da 429', a === 5 && x6.status === 429, `ok=${a}, sexto=${x6.status}`);
    const sv = await api('POST', '/api/auth/send-verification', { email: 'otro@test.com' });
    check('...y ese límite NO gasta el de verificar email (contadores independientes)', sv.status === 200, `status=${sv.status} ${JSON.stringify(sv.body)}`);

    seccion('12. Logs y auditoría en la BD');
    const aud = await q('SELECT accion, count(*)::int n FROM auditoria GROUP BY 1 ORDER BY 1');
    const accs = Object.fromEntries(aud.map((x) => [x.accion, x.n]));
    check('AUDITORIA registra REGISTRO, LOGIN, LOGINFALLIDO, CAMBIOCLAVE y RESETCLAVE', accs.REGISTRO >= 4 && accs.LOGIN >= 3 && accs.LOGINFALLIDO >= 5 && accs.CAMBIOCLAVE === 1 && accs.RESETCLAVE === 1, JSON.stringify(accs));
    const lm = await q('SELECT modulo,accion,nivel, solicitudid FROM logmensajes ORDER BY id LIMIT 1');
    check('LOGMENSAJES: el fallo de correo quedó como ADVERTENCIA (con SOLICITUDID)', lm[0] && lm[0].modulo === 'CORREO' && lm[0].nivel === 'ADVERTENCIA' && !!lm[0].solicitudid, JSON.stringify(lm[0]));
    const filtrado = await q(`SELECT count(*)::int n FROM logmensajes WHERE detalle::text ~ '[0-9]{6}'`);
    check('ningún log contiene un código de 6 dígitos', filtrado[0].n === 0, `n=${filtrado[0].n}`);

    seccion('13. Un error 500 real queda en LOGERRORES (con los datos sensibles ocultos)');
    // Se rompe la BD a propósito (renombrando una tabla un instante) para provocar un error 500 dentro del módulo nuevo.
    await db.query('ALTER TABLE configuraciones RENAME TO configuracionesx');
    r = await api('POST', '/api/auth/register', { nombre: 'Boom', apellido: 'Test', email: 'boom@test.com', telefono: '0991000077', cedula: cedula(17, 1077), password: 'claveSecreta1', tipoUsuario: 'cliente' });
    await db.query('ALTER TABLE configuracionesx RENAME TO configuraciones');
    check('el error interno responde 500 con "error" en texto y código', r.status === 500 && typeof r.body.error === 'string' && r.body.code === 'ERRORINTERNO', JSON.stringify(r.body).slice(0, 150));
    await dormir(500);
    const le = (await q('SELECT * FROM logerrores ORDER BY id DESC LIMIT 1'))[0];
    check('LOGERRORES: módulo AUTH, método POST, ruta, estado 500', le && le.modulo === 'AUTH' && le.metodo === 'POST' && le.ruta === '/api/auth/register' && le.estadohttp === 500, JSON.stringify(le && { m: le.modulo, r: le.ruta, e: le.estadohttp }));
    check('LOGERRORES: stack, huella SHA-256 y mensaje del error real', le && !!le.stack && /^[0-9a-f]{64}$/.test((le.huella || '').trim()) && /configuraciones/i.test(le.mensaje), le && le.mensaje);
    check('LOGERRORES: el SOLICITUDID coincide con el X-Request-Id de la respuesta', le && le.solicitudid === r.headers.get('x-request-id'));
    check('LOGERRORES: la contraseña enviada quedó OCULTA y no aparece en ninguna parte de la fila', le && le.cuerpo && le.cuerpo.password === '[OCULTO]' && !JSON.stringify(le).includes('claveSecreta1'), JSON.stringify(le && le.cuerpo));
    check('LOGERRORES: el resto del cuerpo sí se conserva para depurar', le && le.cuerpo && le.cuerpo.nombre === 'Boom' && le.cuerpo.tipoUsuario === 'cliente');
    r = await api('POST', '/api/auth/login', { email: 'ana@test.com', password: 'claveReset9' });
    check('tras restaurar la tabla todo vuelve a funcionar', r.status === 200);
    const { limpiar } = require(path.join(BACKEND, 'src/shared/services/log.service.js'));
    const lim = limpiar({ email: 'a@b.c', password: 'x', nested: { resetToken: 'y', authorization: 'Bearer z', ok: 1 }, codigo: '123456' });
    check('limpiar() oculta password/token/authorization/código', lim.password === '[OCULTO]' && lim.nested.resetToken === '[OCULTO]' && lim.nested.authorization === '[OCULTO]' && lim.codigo === '[OCULTO]' && lim.email === 'a@b.c' && lim.nested.ok === 1);
  } catch (e) {
    fallos.push('EXCEPCIÓN: ' + e.message); console.log('\n✘ EXCEPCIÓN', e);
  } finally {
    await db.end().catch(() => {}); srv.kill(); await dormir(500); await borrarBaseTemporal().catch(() => {});
  }
  console.log(`\n════════ ${ok} pruebas correctas, ${fallos.length} fallidas ════════`);
  if (fallos.length) { console.log('Fallidas:\n - ' + fallos.join('\n - ')); }
  process.exit(fallos.length ? 1 : 0);
})();
