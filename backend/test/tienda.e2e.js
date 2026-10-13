// Prueba de extremo a extremo de VENDEDORES, PRODUCTOS e IMÁGENES.  Uso:  npm run test:tienda  (desde backend)
// Crea su propia base temporal (vallexpress_tienda) y una carpeta temporal de imágenes; al terminar borra ambas.
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');
const BACKEND = path.resolve(__dirname, '..');
require('dotenv').config({ path: path.join(BACKEND, '.env') });
const { Client } = require('pg');
const sharp = require('sharp');

const PUERTO = 3098;
const BASE = `http://localhost:${PUERTO}`;
const BD = 'vallexpress_tienda';
const UPLOADS = fs.mkdtempSync(path.join(os.tmpdir(), 'vallex_uploads_'));

let ok = 0; const fallos = [];
const check = (n, c, d = '') => { if (c) { ok++; console.log(`  ✔ ${n}`); } else { fallos.push(n); console.log(`  ✘ ${n}  ${d}`); } };
const seccion = (t) => console.log(`\n── ${t}`);
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
const dbConfig = (database) => ({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD, database });

async function api(metodo, ruta, cuerpo, token) {
  const r = await fetch(BASE + ruta, { method: metodo, headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  let body = null; try { body = await r.json(); } catch { /* sin cuerpo */ }
  return { status: r.status, body };
}
function cedula(prov, n) {
  const d = (String(prov).padStart(2, '0') + String(n).padStart(7, '0')).split('').map(Number);
  let s = 0; for (let i = 0; i < 9; i++) { const m = d[i] * (i % 2 === 0 ? 2 : 1); s += m > 9 ? m - 9 : m; }
  return d.join('') + ((10 - (s % 10)) % 10);
}
const imagen = async (w, h, fmt = 'png') => (await sharp({ create: { width: w, height: h, channels: 3, background: { r: 200, g: 60, b: 40 } } })[fmt]().toBuffer()).toString('base64');

let salida = '';
async function codigoDe(email) {
  const re = new RegExp(`\\[DEV\\] Código de verificacion para ${email.replace(/[.+]/g, '\\$&')}: (\\d{6})`);
  for (let i = 0; i < 40; i++) { const m = salida.match(re); if (m) return m[1]; await dormir(100); }
  return null;
}
let contador = 0;
async function registrar(email, nombre, apellido, tipo, extra = {}) {
  contador += 1;
  await api('POST', '/api/auth/send-verification', { email, nombre });
  await api('POST', '/api/auth/verify-email', { email, code: await codigoDe(email) });
  const r = await api('POST', '/api/auth/register', { nombre, apellido, email, telefono: `09920000${String(contador).padStart(2, '0')}`, cedula: cedula(17, 2000 + contador), password: 'secreto1', tipoUsuario: tipo, ...extra });
  return { token: r.body?.token, usuario: r.body?.usuario };
}

(async () => {
  const admin = new Client(dbConfig('postgres')); await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${BD} WITH (FORCE)`); await admin.query(`CREATE DATABASE ${BD}`); await admin.end();
  const db = new Client(dbConfig(BD)); await db.connect();
  await db.query(fs.readFileSync(path.join(BACKEND, '..', 'database', 'schema.sql'), 'utf8'));
  const q = async (sql, p) => (await db.query(sql, p)).rows;

  const srv = spawn(process.execPath, ['src/server.js'], { cwd: BACKEND, env: { ...process.env, NODE_ENV: 'development', PORT: String(PUERTO), DB_NAME: BD, LIMITES_DESACTIVADOS: 'true', UPLOADS_DIR: UPLOADS } });
  srv.stdout.on('data', (d) => { salida += d.toString(); }); srv.stderr.on('data', (d) => { salida += d.toString(); });

  try {
    for (let i = 0; i < 50; i++) { try { if ((await fetch(`${BASE}/api/health`)).ok) break; } catch { /* aún no */ } await dormir(200); }

    const luis = await registrar('luis@test.com', 'Luis', 'Mora', 'vendedor', { nombreNegocio: 'Pizzería Luis' });
    const ana = await registrar('ana@test.com', 'Ana', 'Pérez', 'vendedor', { nombreNegocio: 'Café Ana' });
    const cli = await registrar('carlos@test.com', 'Carlos', 'Ruiz', 'cliente');
    const T = { luis: luis.token, ana: ana.token, cli: cli.token };
    const venLuis = (await q("SELECT cusuario AS vendedor FROM tnegocios WHERE cusuario='lmora' AND fhasta>now()"))[0].vendedor;
    const venAna = (await q("SELECT cusuario AS vendedor FROM tnegocios WHERE cusuario='aperez' AND fhasta>now()"))[0].vendedor;
    let r;

    seccion('1. Vendedores: consultas públicas');
    r = await api('GET', '/api/vendedores');
    check('lista pública sin token: 200 y 2 vendedores', r.status === 200 && r.body.vendedores.length === 2, JSON.stringify(r.body).slice(0, 120));
    const v = r.body.vendedores.find((x) => x.usuarioId === 'lmora');
    check('formato: id = usuarioId = lmora, categoría "Otros" (099), calificación numérica', v && v.id === 'lmora' && v.categoria === 'Otros' && v.categoriaCodigo === '099' && v.calificacionPromedio === 0 && v.logo === null);
    check('PRIVACIDAD: la lista pública NO expone email ni teléfono del dueño', v.usuario && v.usuario.nombre === 'Luis' && v.usuario.email === undefined && v.usuario.telefono === undefined);
    r = await api('GET', `/api/vendedores/${venLuis}`);
    check('GET /:id público: 200', r.status === 200 && r.body.vendedor.id === venLuis);
    r = await api('GET', '/api/vendedores/A-B');
    check('id mal formado: 400', r.status === 400 && /inválido/.test(r.body.error));
    r = await api('GET', '/api/vendedores/noexiste');
    check('id inexistente: 404', r.status === 404);

    seccion('2. Vendedores: perfil propio y permisos');
    r = await api('GET', '/api/vendedores/perfil/mi-negocio', null, T.luis);
    check('mi-negocio: 200 y SÍ incluye email y teléfono (es el propio dueño)', r.status === 200 && r.body.vendedor.usuario.email === 'luis@test.com');
    r = await api('GET', '/api/vendedores/perfil/mi-negocio', null, T.cli);
    check('cliente en ruta de vendedor: 403', r.status === 403);
    r = await api('GET', '/api/vendedores/perfil/mi-negocio');
    check('sin token: 401', r.status === 401);
    r = await api('POST', '/api/vendedores', { nombreNegocio: 'Otro negocio' }, T.luis);
    check('crear un 2.º negocio: 409', r.status === 409);

    seccion('3. Vendedores: actualizar (categoría, horario, validaciones)');
    r = await api('PUT', '/api/vendedores/perfil/actualizar', { nombreNegocio: 'Pizzería Don Luis', descripcion: 'Las mejores', categoria: 'Comida', costoDelivery: 1.5, radioCobertura: 5, abiertoAhora: true, horarioApertura: '08:00', horarioCierre: '22:30' }, T.luis);
    const a = r.body.vendedor || {};
    check('actualizar: 200 con nombre, categoría "Comida" (001), costo numérico y horario', r.status === 200 && a.nombreNegocio === 'Pizzería Don Luis' && a.categoria === 'Comida' && a.categoriaCodigo === '001' && a.costoDelivery === 1.5 && a.horarioApertura === '08:00' && a.horarioCierre === '22:30' && a.abiertoAhora === true, JSON.stringify(a).slice(0, 200));
    let h = await q('SELECT dia, apertura::text a, cierre::text c FROM thorariosnegocio WHERE cusuario=$1 AND fhasta>now() ORDER BY dia', [venLuis]);
    check('el horario quedó en THORARIOSNEGOCIO: 7 días (1..7) 08:00 - 22:30', h.length === 7 && h[0].dia === 1 && h[6].dia === 7 && h.every((x) => x.a === '08:00:00' && x.c === '22:30:00'), JSON.stringify(h[0]));
    await api('PUT', '/api/vendedores/perfil/actualizar', { horarioCierre: '23:00' }, T.luis);
    h = await q('SELECT apertura::text a, cierre::text c FROM thorariosnegocio WHERE cusuario=$1 AND fhasta>now()', [venLuis]);
    check('cambiar solo el cierre: sigue habiendo 7 filas (sin duplicar) y la apertura intacta', h.length === 7 && h.every((x) => x.a === '08:00:00' && x.c === '23:00:00'));
    r = await api('PUT', '/api/vendedores/perfil/actualizar', { categoria: 'Pizza' }, T.luis);
    check('categoría libre "Pizza": se devuelve igual y se guarda 099 + texto original', r.body.vendedor.categoria === 'Pizza' && r.body.vendedor.categoriaCodigo === '099' && (await q('SELECT datosextra FROM tnegocios WHERE cusuario=$1 AND fhasta>now()', [venLuis]))[0].datosextra === 'categoria=Pizza');
    r = await api('PUT', '/api/vendedores/perfil/actualizar', { categoria: 'Bebida' }, T.luis);
    check('"Bebida" (singular) se reconoce: "Bebidas" (002) y se limpia el texto extra', r.body.vendedor.categoria === 'Bebidas' && r.body.vendedor.categoriaCodigo === '002' && (await q('SELECT datosextra FROM tnegocios WHERE cusuario=$1 AND fhasta>now()', [venLuis]))[0].datosextra === null);
    for (const [cuerpo, quehay] of [[{ horarioApertura: '25:99' }, 'hora inválida'], [{ nombreNegocio: 'ab' }, 'nombre corto'], [{ costoDelivery: -1 }, 'costo negativo'], [{ abiertoAhora: 'quizas' }, 'booleano inválido']]) {
      r = await api('PUT', '/api/vendedores/perfil/actualizar', cuerpo, T.luis);
      check(`validación: ${quehay} -> 400`, r.status === 400, JSON.stringify(r.body).slice(0, 100));
    }
    r = await api('PUT', '/api/vendedores/perfil/actualizar', { descripcion: 'x' }, T.cli);
    check('cliente no puede actualizar un negocio: 403', r.status === 403);
    r = await api('PATCH', '/api/vendedores/perfil/ubicacion', { latitud: -0.18, longitud: -78.47 }, T.luis);
    check('ubicación válida: 200 con números', r.status === 200 && r.body.ubicacion.latitud === -0.18 && r.body.ubicacion.longitud === -78.47);
    const loc = (await q("SELECT d.ctipodireccion t, d.latitud::float la FROM tnegocios n JOIN tpersonadirecciones d ON d.cdireccion=n.cdireccion AND d.fhasta>now() WHERE n.cusuario=$1 AND n.fhasta>now()", [venLuis]))[0];
    check('el local es una dirección de la persona tipo LOC (no hay lat/long propios en TNEGOCIOS)', loc && loc.t === 'LOC' && loc.la === -0.18);
    r = await api('PATCH', '/api/vendedores/perfil/ubicacion', { latitud: -0.19, longitud: -78.48 }, T.luis);
    check('mover el local actualiza la MISMA dirección (una sola fila vigente) y la API la devuelve', r.status === 200 && (await q("SELECT count(*)::int n FROM tpersonadirecciones WHERE ctipodireccion='LOC' AND fhasta>now()"))[0].n === 1 && (await api('GET', `/api/vendedores/${venLuis}`)).body.vendedor.latitud === -0.19);
    r = await api('PATCH', '/api/vendedores/perfil/ubicacion', { latitud: 200, longitud: 0 }, T.luis);
    check('latitud fuera de rango: 400', r.status === 400);
    r = await api('PATCH', '/api/vendedores/perfil/ubicacion', { latitud: -0.18 }, T.luis);
    check('falta la longitud: 400 "son requeridas"', r.status === 400 && /requeridas/.test(r.body.error));
    check('los cambios del negocio quedan versionados en TNEGOCIOS (filas cerradas)', (await q('SELECT count(*)::int n FROM tnegocios WHERE cusuario=$1 AND fhasta<now()', [venLuis]))[0].n >= 3);

    seccion('4. Visibilidad: solo vendedores aprobados');
    await db.query("UPDATE tnegocios SET aprobacion='001' WHERE cusuario=$1 AND fhasta>now()", [venAna]);
    r = await api('GET', '/api/vendedores');
    check('un vendedor PENDIENTE desaparece de la lista pública', r.body.vendedores.length === 1 && r.body.vendedores[0].id === venLuis);
    r = await api('GET', `/api/vendedores/${venAna}`);
    check('...y su ficha pública da 404', r.status === 404);

    seccion('5. Imágenes (sharp: validación, WebP, tamaños, deduplicación)');
    const png = await imagen(900, 700);
    r = await api('PATCH', '/api/vendedores/perfil/logo', { logo: `data:image/png;base64,${png}` }, T.luis);
    check('logo (data URI): 200 y devuelve una URL de /uploads/logo/..._m.webp', r.status === 200 && /^http:\/\/localhost:3098\/uploads\/logo\/[0-9a-f]{24}_m\.webp$/.test(r.body.logo), JSON.stringify(r.body).slice(0, 120));
    const urlLogo = r.body.logo;
    const res = await fetch(urlLogo);
    check('la URL se sirve como image/webp con caché larga', res.status === 200 && res.headers.get('content-type') === 'image/webp' && /max-age=604800/.test(res.headers.get('cache-control') || ''));
    const ar = (await q("SELECT * FROM archivos WHERE categoria='LOGO'"))[0];
    check('ARCHIVOS: LOGO, webp optimizado, hash SHA-256, propietario lmora, ≤512 px, código ARC-', ar && /^ARC-\d{6}$/.test(ar.archivo) && ar.mime === 'image/webp' && ar.optimizado === true && /^[0-9a-f]{64}$/.test(ar.hash.trim()) && ar.propietario === 'lmora' && ar.ancho <= 512 && Number(ar.bytes) > 0, JSON.stringify(ar && { a: ar.archivo, w: ar.ancho }));
    check('TNEGOCIOS.LOGO apunta al código del archivo (relación por código)', (await q('SELECT logo FROM tnegocios WHERE cusuario=$1 AND fhasta>now()', [venLuis]))[0].logo === ar.archivo);
    const dir = path.join(UPLOADS, 'logo'); const base = path.basename(ar.rutaoriginal, '.webp');
    check('se guardaron las 3 versiones en disco (principal, mediana, miniatura)', ['.webp', '_m.webp', '_t.webp'].every((s) => fs.existsSync(path.join(dir, base + s))));
    check('optimizada: pesa mucho menos que el PNG original', Number(ar.bytes) < Buffer.from(png, 'base64').length / 2, `${ar.bytes} vs ${Buffer.from(png, 'base64').length}`);
    await api('PATCH', '/api/vendedores/perfil/logo', { logo: png }, T.luis);
    check('la MISMA imagen subida otra vez no se duplica', (await q("SELECT count(*)::int n FROM archivos WHERE categoria='LOGO'"))[0].n === 1);
    r = await api('GET', `/api/vendedores/${venLuis}`);
    check('la ficha del vendedor trae logo y logoMiniatura (_t.webp)', r.body.vendedor.logo === urlLogo && /_t\.webp$/.test(r.body.vendedor.logoMiniatura));
    r = await api('PATCH', '/api/vendedores/perfil/banner', { banner: await imagen(2400, 1200, 'jpeg') }, T.luis);
    const ban = (await q("SELECT ancho, alto FROM archivos WHERE categoria='BANNER'"))[0];
    check('PATCH /perfil/banner (ruta que la app usaba y no existía): 200 y recortada a 1600x600', r.status === 200 && ban && ban.ancho === 1600 && ban.alto === 600, JSON.stringify(ban));
    const girada = await sharp(Buffer.from(await imagen(100, 50, 'jpeg'), 'base64')).jpeg().withMetadata({ orientation: 6 }).toBuffer();
    r = await api('PATCH', '/api/vendedores/perfil/logo', { logo: girada.toString('base64') }, T.luis);
    const gir = (await q("SELECT ancho, alto FROM archivos WHERE categoria='LOGO' ORDER BY creadoen DESC LIMIT 1"))[0];
    check('se corrige la orientación EXIF (100x50 con giro 90° queda más alta que ancha)', r.status === 200 && gir.alto > gir.ancho, JSON.stringify(gir));
    for (const [valor, quehay] of [[Buffer.from('hola mundo, esto no es una imagen').toString('base64'), 'texto que no es imagen'], ['esto no es base64 !!!', 'base64 inválido'], [Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>').toString('base64'), 'SVG (puede traer scripts)']]) {
      r = await api('PATCH', '/api/vendedores/perfil/logo', { logo: valor }, T.luis);
      check(`rechaza ${quehay}: 400`, r.status === 400, JSON.stringify(r.body).slice(0, 100));
    }
    r = await api('PATCH', '/api/vendedores/perfil/logo', { logo: 'A'.repeat(11 * 1024 * 1024) }, T.luis);
    check('imagen enorme (>10 MB): 413', r.status === 413, String(r.status));

    seccion('6. Productos: crear y validar');
    const nuevo = { nombre: 'Pizza Margarita', precio: 5.5, descripcion: 'Con albahaca', categoria: 'Comida', stock: 10, tiempoPreparacion: 15 };
    r = await api('POST', '/api/productos', nuevo, T.luis);
    const p = r.body.producto || {};
    check('crear: 201, id PRO-, vendedor VEN-, precio numérico, disponible y estado 001', r.status === 201 && /^PRO-\d{6}$/.test(p.id) && p.vendedorId === venLuis && p.precio === 5.5 && p.disponible === true && p.estado === '001' && p.stock === 10 && p.controlaStock === true && p.categoria === 'Comida', JSON.stringify(p).slice(0, 220));
    r = await api('POST', '/api/productos', { nombre: 'Agua', precio: 1 }, T.luis);
    check('sin stock informado: no se controla stock y queda disponible', r.status === 201 && r.body.producto.controlaStock === false && r.body.producto.disponible === true);
    r = await api('POST', '/api/productos', { nombre: 'Tiramisú', precio: 3, stock: 0 }, T.luis);
    check('con stock 0: nace AGOTADO (002) y no disponible', r.status === 201 && r.body.producto.estado === '002' && r.body.producto.disponible === false);
    for (const [cuerpo, quehay] of [[{ precio: 1 }, 'falta el nombre'], [{ nombre: 'ab', precio: 1 }, 'nombre corto'], [{ nombre: 'Pizza X' }, 'falta el precio'], [{ nombre: 'Pizza X', precio: -1 }, 'precio negativo'], [{ nombre: 'Pizza X', precio: 1, stock: -5 }, 'stock negativo'], [{ nombre: 'Pizza X', precio: 1, tiempoPreparacion: -1 }, 'tiempo negativo']]) {
      r = await api('POST', '/api/productos', cuerpo, T.luis);
      check(`validación: ${quehay} -> 400`, r.status === 400, JSON.stringify(r.body).slice(0, 90));
    }
    r = await api('POST', '/api/productos', nuevo, T.cli);
    check('un cliente no puede crear productos: 403', r.status === 403);
    r = await api('POST', '/api/productos', nuevo);
    check('sin token: 401', r.status === 401);
    r = await api('POST', '/api/productos', nuevo, T.ana);
    check('vendedor NO aprobado no puede crear productos: 403 NEGOCIONOAPROBADO', r.status === 403 && r.body.code === 'NEGOCIONOAPROBADO', JSON.stringify(r.body));
    await db.query("UPDATE tnegocios SET aprobacion='002' WHERE cusuario=$1 AND fhasta>now()", [venAna]);
    await api('POST', '/api/productos', { nombre: 'Café americano', precio: 1.25, stock: 50 }, T.ana);

    seccion('7. Productos: consultas');
    r = await api('GET', '/api/productos');
    check('lista pública: productos con su vendedor y total', r.status === 200 && r.body.productos.length === 4 && r.body.total === 4 && r.body.productos[0].vendedor && r.body.productos[0].vendedor.nombreNegocio, JSON.stringify(r.body).slice(0, 100));
    r = await api('GET', '/api/productos?limite=1');
    check('paginación ?limite=1: 1 producto, total 4', r.body.productos.length === 1 && r.body.total === 4 && r.body.limite === 1);
    r = await api('GET', '/api/productos?limite=0');
    check('límite inválido: 400', r.status === 400);
    r = await api('GET', `/api/productos/vendedor/${venLuis}`);
    check('productos de un vendedor: solo los suyos (3)', r.status === 200 && r.body.productos.length === 3 && r.body.productos.every((x) => x.vendedorId === venLuis));
    check('vendedor mal formado: 400 · inexistente: 404', (await api('GET', '/api/productos/vendedor/X-Y')).status === 400 && (await api('GET', '/api/productos/vendedor/noexiste')).status === 404);
    r = await api('GET', '/api/productos/mis-productos', null, T.luis);
    check('mis-productos: los 3 propios', r.status === 200 && r.body.productos.length === 3);
    check('mis-productos como cliente: 403', (await api('GET', '/api/productos/mis-productos', null, T.cli)).status === 403);
    r = await api('GET', `/api/productos/${p.id}`);
    check('GET /:id: 200 con vendedor y calificación', r.status === 200 && r.body.producto.id === p.id && r.body.producto.vendedor.calificacionPromedio === 0);
    check('id mal formado: 400 · inexistente: 404', (await api('GET', '/api/productos/abc')).status === 400 && (await api('GET', '/api/productos/PRO-999999')).status === 404);
    await db.query("UPDATE tnegocios SET aprobacion='001' WHERE cusuario=$1 AND fhasta>now()", [venAna]);
    r = await api('GET', '/api/productos');
    check('los productos de un vendedor PENDIENTE no salen en la lista pública', r.body.productos.length === 3 && r.body.productos.every((x) => x.vendedorId === venLuis));
    await db.query("UPDATE tnegocios SET aprobacion='002' WHERE cusuario=$1 AND fhasta>now()", [venAna]);

    seccion('8. Productos: actualizar, disponibilidad, propiedad');
    r = await api('PUT', `/api/productos/${p.id}`, { precio: 6, nombre: 'Pizza Margarita XL', categoria: 'Bebida' }, T.luis);
    check('actualizar como dueño: precio 6, nombre nuevo, categoría "Bebidas"', r.status === 200 && r.body.producto.precio === 6 && r.body.producto.nombre === 'Pizza Margarita XL' && r.body.producto.categoria === 'Bebidas');
    r = await api('PUT', `/api/productos/${p.id}`, { precio: 1 }, T.ana);
    check('SEGURIDAD: otro vendedor no puede modificarlo: 404 "no te pertenece"', r.status === 404 && /no te pertenece/.test(r.body.error));
    r = await api('PUT', `/api/productos/${p.id}`, { stock: 0 }, T.luis);
    check('stock a 0: pasa a AGOTADO (002)', r.body.producto.estado === '002' && r.body.producto.disponible === false);
    r = await api('PUT', `/api/productos/${p.id}`, { stock: 5 }, T.luis);
    check('stock a 5: vuelve a DISPONIBLE (001)', r.body.producto.estado === '001' && r.body.producto.disponible === true && r.body.producto.stock === 5);
    r = await api('PATCH', `/api/productos/${p.id}/disponible`, { disponible: false }, T.luis);
    check('disponible=false: estado 003 (no disponible)', r.status === 200 && r.body.producto.disponible === false && r.body.producto.estado === '003');
    r = await api('PATCH', `/api/productos/${p.id}/disponible`, { disponible: true }, T.luis);
    check('disponible=true: estado 001', r.body.producto.estado === '001' && r.body.producto.disponible === true);
    check('disponible no booleano ("si"): 400', (await api('PATCH', `/api/productos/${p.id}/disponible`, { disponible: 'si' }, T.luis)).status === 400);
    check('disponible por otro vendedor: 404', (await api('PATCH', `/api/productos/${p.id}/disponible`, { disponible: false }, T.ana)).status === 404);

    seccion('9. Productos: imagen, borrado lógico y versionado');
    r = await api('PUT', `/api/productos/${p.id}`, { imagen: await imagen(1500, 1000, 'jpeg') }, T.luis);
    check('imagen en base64: se optimiza y devuelve URL /uploads/producto/..._m.webp con miniatura', r.status === 200 && /\/uploads\/producto\/[0-9a-f]{24}_m\.webp$/.test(r.body.producto.imagen) && /_t\.webp$/.test(r.body.producto.imagenMiniatura), JSON.stringify(r.body.producto).slice(0, 120));
    const imgProd = r.body.producto.imagen;
    r = await api('PUT', `/api/productos/${p.id}`, { imagen: 'http://otro.com/foto.jpg' }, T.luis);
    check('una URL en "imagen" se interpreta como "sin cambios"', r.body.producto.imagen === imgProd);
    r = await api('PUT', `/api/productos/${p.id}`, { imagen: 'esto no es una imagen' }, T.luis);
    check('imagen inválida: 400', r.status === 400);
    r = await api('PUT', `/api/productos/${p.id}`, { imagen: null }, T.luis);
    check('imagen null: se quita', r.status === 200 && r.body.producto.imagen === null);
    check('el cambio de precio quedó versionado en HISTPRODUCTOS', (await q('SELECT count(*)::int n FROM tproductos WHERE cproducto=$1 AND fhasta<now()', [p.id]))[0].n >= 3);
    await db.query('UPDATE tproductos SET totalvendidos = 5 WHERE cproducto=$1 AND fhasta>now()', [p.id]);
    const antes = (await q('SELECT count(*)::int n FROM tproductos WHERE cproducto=$1 AND fhasta<now()', [p.id]))[0].n;
    await db.query('UPDATE tproductos SET totalvendidos = 6 WHERE cproducto=$1 AND fhasta>now()', [p.id]);
    check('TOTALVENDIDOS es columna volátil: no genera versiones', (await q('SELECT count(*)::int n FROM tproductos WHERE cproducto=$1 AND fhasta<now()', [p.id]))[0].n === antes);
    check('borrar producto ajeno: 404', (await api('DELETE', `/api/productos/${p.id}`, null, T.ana)).status === 404);
    r = await api('DELETE', `/api/productos/${p.id}`, null, T.luis);
    check('borrar como dueño: 200', r.status === 200);
    check('luego GET /:id da 404 y no está en la lista', (await api('GET', `/api/productos/${p.id}`)).status === 404 && !(await api('GET', '/api/productos')).body.productos.some((x) => x.id === p.id));
    check('BORRADO LÓGICO: la fila sigue en la BD con ELIMINADOEN', (await q('SELECT eliminadoen FROM tproductos WHERE cproducto=$1 AND fhasta>now()', [p.id]))[0].eliminadoen !== null);

    seccion('10. Foto de perfil de usuario (antes respondía 501)');
    r = await api('POST', '/api/usuarios/foto-perfil', { foto: await imagen(800, 800) }, T.cli);
    check('subir foto: 200 y URL /uploads/perfil/..._m.webp', r.status === 200 && /\/uploads\/perfil\/[0-9a-f]{24}_m\.webp$/.test(r.body.data.fotoPerfil), JSON.stringify(r.body).slice(0, 120));
    r = await api('GET', '/api/auth/profile', null, T.cli);
    check('el perfil devuelve fotoPerfil (URL) y la foto vigente (TPERSONAIMAGENES) guarda el código ARC-', /_m\.webp$/.test(r.body.usuario.fotoPerfil) && /^ARC-/.test((await q("SELECT foto FROM vusuarios WHERE usuario='cruiz'"))[0].foto));
    check('foto inválida: 400 · sin foto: 400', (await api('POST', '/api/usuarios/foto-perfil', { foto: 'basura' }, T.cli)).status === 400 && (await api('POST', '/api/usuarios/foto-perfil', {}, T.cli)).status === 400);

    seccion('11. Eliminar negocio');
    r = await api('DELETE', '/api/vendedores/perfil/eliminar', null, T.luis);
    check('eliminar negocio: 200', r.status === 200);
    check('desaparece de la lista y de mi-negocio (404), pero la fila sigue con ELIMINADOEN', (await api('GET', `/api/vendedores/${venLuis}`)).status === 404 && (await api('GET', '/api/vendedores/perfil/mi-negocio', null, T.luis)).status === 404 && (await q('SELECT eliminadoen FROM tnegocios WHERE cusuario=$1 AND fhasta>now()', [venLuis]))[0].eliminadoen !== null);
  } catch (e) {
    fallos.push(`EXCEPCIÓN: ${e.message}`); console.log('\n✘ EXCEPCIÓN', e);
  } finally {
    await db.end().catch(() => {}); srv.kill(); await dormir(500);
    const a2 = new Client(dbConfig('postgres')); await a2.connect().then(() => a2.query(`DROP DATABASE IF EXISTS ${BD} WITH (FORCE)`)).catch(() => {}); await a2.end().catch(() => {});
    fs.rmSync(UPLOADS, { recursive: true, force: true });
  }
  console.log(`\n════════ ${ok} pruebas correctas, ${fallos.length} fallidas ════════`);
  if (fallos.length) console.log(`Fallidas:\n - ${fallos.join('\n - ')}`);
  process.exit(fallos.length ? 1 : 0);
})();
