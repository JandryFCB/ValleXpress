// Arnés común de las pruebas de extremo a extremo: crea una BD y una carpeta de imágenes TEMPORALES, levanta el
// servidor contra ellas, ofrece utilidades (api, registrar usuarios, sockets) y al terminar lo borra todo.
// No toca la base de desarrollo. Uso:  const t = crearArnes({ puerto: 3097, bd: 'vallexpress_pedidos' });
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');
const BACKEND = path.resolve(__dirname, '..');
require('dotenv').config({ path: path.join(BACKEND, '.env') });
const { Client } = require('pg');
const sharp = require('sharp');
const { io } = require('socket.io-client');

module.exports = function crearArnes({ puerto, bd, env = {} }) {
  const BASE = `http://localhost:${puerto}`;
  const UPLOADS = fs.mkdtempSync(path.join(os.tmpdir(), 'vallex_uploads_'));
  const dbConfig = (database) => ({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, password: process.env.DB_PASSWORD, database });
  const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
  let ok = 0; const fallos = [];
  let salida = ''; let srv; let db; let contador = 0; const sockets = [];

  const check = (n, c, d = '') => { if (c) { ok++; console.log(`  ✔ ${n}`); } else { fallos.push(n); console.log(`  ✘ ${n}  ${d}`); } };
  const seccion = (t) => console.log(`\n── ${t}`);

  async function api(metodo, ruta, cuerpo, token) {
    const r = await fetch(BASE + ruta, { method: metodo, headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
    let body = null; try { body = await r.json(); } catch { /* sin cuerpo */ }
    return { status: r.status, body };
  }

  // Cédulas ecuatorianas válidas (mismo algoritmo módulo 10 del backend)
  function cedula(prov, n) {
    const d = (String(prov).padStart(2, '0') + String(n).padStart(7, '0')).split('').map(Number);
    let s = 0; for (let i = 0; i < 9; i++) { const m = d[i] * (i % 2 === 0 ? 2 : 1); s += m > 9 ? m - 9 : m; }
    return d.join('') + ((10 - (s % 10)) % 10);
  }
  const imagen = async (w, h, fmt = 'png') => (await sharp({ create: { width: w, height: h, channels: 3, background: { r: 200, g: 60, b: 40 } } })[fmt]().toBuffer()).toString('base64');

  // Los códigos se imprimen en la consola del servidor en desarrollo (en las pruebas no hay proveedor de correo).
  // tipo: 'verificacion' | 'reset'. "desde" = posición de la consola desde la que buscar (ver marca()).
  const marca = () => salida.length;
  async function codigoDe(email, tipo = 'verificacion', desde = 0) {
    const re = new RegExp(`\\[DEV\\] Código de ${tipo} para ${email.replace(/[.+]/g, '\\$&')}: (\\d{6})`, 'g');
    for (let i = 0; i < 40; i++) { const m = [...salida.slice(desde).matchAll(re)].pop(); if (m) return m[1]; await dormir(100); }
    return null;
  }

  // Verifica el correo (leyendo el código de la consola del servidor) y registra al usuario. Devuelve { token, usuario }.
  async function registrar(email, nombre, apellido, tipo, extra = {}) {
    contador += 1;
    await api('POST', '/api/auth/send-verification', { email, nombre });
    await api('POST', '/api/auth/verify-email', { email, code: await codigoDe(email) });
    const r = await api('POST', '/api/auth/register', { nombre, apellido, email, telefono: `09930000${String(contador).padStart(2, '0')}`, cedula: cedula(17, 3000 + contador), password: 'secreto1', tipoUsuario: tipo, ...extra });
    return { token: r.body?.token, refreshToken: r.body?.refreshToken, usuario: r.body?.usuario };
  }

  // Socket.IO: conectar con un token, emitir con respuesta (ack) y esperar un evento
  function conectar(token) {
    return new Promise((resolve) => {
      const s = io(BASE, { auth: { token }, transports: ['websocket'], reconnection: false });
      sockets.push(s);
      s.on('connect', () => resolve(s));
      s.on('connect_error', (e) => resolve({ error: e.message }));
    });
  }
  const emitir = (s, evento, payload) => new Promise((r) => { s.emit(evento, payload, r); });
  const esperar = (s, evento, ms = 3000) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(evento, (d) => { clearTimeout(t); r(d); }); });

  async function iniciar() {
    const admin = new Client(dbConfig('postgres')); await admin.connect();
    await admin.query(`DROP DATABASE IF EXISTS ${bd} WITH (FORCE)`); await admin.query(`CREATE DATABASE ${bd}`); await admin.end();
    db = new Client(dbConfig(bd)); await db.connect();
    // La base se arma con las mismas migraciones que usa Docker, en orden
    const carpeta = path.join(BACKEND, '..', 'database', 'migraciones');
    for (const archivo of fs.readdirSync(carpeta).filter((f) => f.endsWith('.sql')).sort()) {
      await db.query(fs.readFileSync(path.join(carpeta, archivo), 'utf8'));
    }
    srv = spawn(process.execPath, ['src/server.js'], { cwd: BACKEND, env: { ...process.env, NODE_ENV: 'development', PORT: String(puerto), DB_NAME: bd, LIMITES_DESACTIVADOS: 'true', UPLOADS_DIR: UPLOADS, BREVO_API_KEY: '', ...env } });
    srv.stdout.on('data', (d) => { salida += d.toString(); }); srv.stderr.on('data', (d) => { salida += d.toString(); });
    for (let i = 0; i < 50; i++) { try { if ((await fetch(`${BASE}/api/health`)).ok) break; } catch { /* aún no */ } await dormir(200); }
    return { db, q: async (sql, p) => (await db.query(sql, p)).rows };
  }

  async function finalizar(error) {
    if (error) { fallos.push(`EXCEPCIÓN: ${error.message}`); console.log('\n✘ EXCEPCIÓN', error); }
    sockets.forEach((s) => s.close());
    await db?.end().catch(() => {}); srv?.kill(); await dormir(500);
    const a = new Client(dbConfig('postgres')); await a.connect().then(() => a.query(`DROP DATABASE IF EXISTS ${bd} WITH (FORCE)`)).catch(() => {}); await a.end().catch(() => {});
    fs.rmSync(UPLOADS, { recursive: true, force: true });
    console.log(`\n════════ ${ok} pruebas correctas, ${fallos.length} fallidas ════════`);
    if (fallos.length) console.log(`Fallidas:\n - ${fallos.join('\n - ')}`);
    process.exit(fallos.length ? 1 : 0);
  }

  return { check, seccion, dormir, marca, codigoDe, api, cedula, imagen, iniciar, registrar, finalizar, conectar, emitir, esperar, BASE };
};
