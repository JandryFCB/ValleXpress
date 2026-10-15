// Simulador de una entrega completa, SOLO para desarrollo: hace de NEGOCIO (acepta y deja listo el pedido) y de
// REPARTIDOR (se conecta, lo acepta y recorre el camino enviando su GPS por socket). Sirve para ver en el celular
// del cliente la moto moviéndose en el mapa sin tener un segundo celular.
//
//   node scripts/simular-entrega.js            espera a que el cliente haga un pedido y lo lleva hasta entregarlo
//   node scripts/simular-entrega.js 5          lleva el pedido #5
//
// Opciones (variables de entorno): API (http://localhost:3000), VENDEDOR (jcayapa), REPARTIDOR (pvera),
// CLAVE (secreto1), PASO_MS (2500 = cada cuánto se mueve), METROS (60 = cuánto avanza en cada paso).
const { io } = require('socket.io-client');

const API = process.env.API || 'http://localhost:3000';
const VENDEDOR = process.env.VENDEDOR || 'jcayapa';
const REPARTIDOR = process.env.REPARTIDOR || 'pvera';
const CLAVE = process.env.CLAVE || 'secreto1';
const PASOMS = Number(process.env.PASO_MS || 2500);
const METROS = Number(process.env.METROS || 60);
const dormir = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...m) => console.log(new Date().toLocaleTimeString(), ...m);

async function api(metodo, ruta, cuerpo, token) {
  const r = await fetch(`${API}/api${ruta}`, { method: metodo, headers: { 'Content-Type': 'application/json', ...(token && { Authorization: `Bearer ${token}` }) }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  let body = null; try { body = await r.json(); } catch { /* sin cuerpo */ }
  if (r.status >= 400) throw new Error(`${metodo} ${ruta}: ${r.status} ${body?.error || ''}`);
  return body;
}
const entrar = async (usuario) => (await api('POST', '/auth/login', { email: usuario, password: CLAVE })).token;

// Distancia en metros (haversine) y puntos intermedios cada METROS, con una curva en L para que parezca una calle
function metros(a, b) {
  const rad = (g) => (g * Math.PI) / 180;
  const h = Math.sin(rad(b.lat - a.lat) / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lng - a.lng) / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(h));
}
function tramo(a, b) {
  const n = Math.max(1, Math.round(metros(a, b) / METROS));
  return Array.from({ length: n }, (_, i) => ({ lat: a.lat + ((b.lat - a.lat) * (i + 1)) / n, lng: a.lng + ((b.lng - a.lng) * (i + 1)) / n }));
}
const ruta = (a, b) => [...tramo(a, { lat: a.lat, lng: b.lng }), ...tramo({ lat: a.lat, lng: b.lng }, b)];
const rumbo = (a, b) => ((Math.atan2(b.lng - a.lng, b.lat - a.lat) * 180) / Math.PI + 360) % 360;

async function recorrer(socket, desde, hasta, etiqueta) {
  const puntos = ruta(desde, hasta);
  log(`🛵 ${etiqueta}: ${Math.round(metros(desde, hasta))} m en ${puntos.length} pasos`);
  let previo = desde;
  for (const p of puntos) {
    // Velocidad informada: la de una moto en la ciudad (~22 km/h), aunque la simulación avance más rápido
    const ack = await new Promise((r) => socket.timeout(5000).emit('repartidor:ubicacion', { lat: p.lat, lng: p.lng, velocidad: 6, rumbo: rumbo(previo, p) }, (err, res) => r(err ? { ok: false } : res)));
    if (!ack?.ok) log('   ubicación no aceptada:', ack?.error);
    previo = p;
    await dormir(PASOMS);
  }
}

(async () => {
  const V = await entrar(VENDEDOR);
  const R = await entrar(REPARTIDOR);
  log(`Negocio: ${VENDEDOR} · Repartidor: ${REPARTIDOR}`);

  // 1) El pedido: el indicado, o el próximo que haga un cliente
  let id = Number(process.argv[2]) || null;
  if (!id) {
    log('Esperando que un cliente haga un pedido en el negocio… (Ctrl+C para salir)');
    for (let i = 0; i < 200 && !id; i++) {
      const { pedidos } = await api('GET', '/mi-negocio/pedidos?estado=activos', null, V);
      id = pedidos.find((p) => ['pendiente', 'confirmado', 'preparando', 'listo'].includes(p.estado))?.id || null;
      if (!id) await dormir(3000);
    }
    if (!id) throw new Error('Nadie hizo un pedido');
  }
  let pedido = (await api('GET', `/pedidos/${id}`, null, V)).pedido;
  log(`📦 Pedido #${id} (${pedido.estado}) para ${pedido.cliente?.nombre}`);

  // 2) El negocio lo acepta, lo prepara y lo deja listo
  const pasos = { pendiente: ['confirmado', 'preparando', 'listo'], confirmado: ['preparando', 'listo'], preparando: ['listo'] }[pedido.estado] || [];
  for (const estado of pasos) {
    await dormir(4000);
    await api('PATCH', `/mi-negocio/pedidos/${id}/estado`, { estado, ...(estado === 'confirmado' && { tiempoEstimado: 30 }) }, V);
    log(`🏪 Negocio: ${estado}`);
  }

  // 3) El repartidor se conecta cerca del negocio y lo acepta
  pedido = (await api('GET', `/pedidos/${id}`, null, V)).pedido;
  const negocio = { lat: pedido.negocio.local.latitud, lng: pedido.negocio.local.longitud };
  const cliente = { lat: pedido.entrega.latitud, lng: pedido.entrega.longitud };
  const salida = { lat: negocio.lat + 0.006, lng: negocio.lng - 0.005 };      // ~900 m del negocio
  const socket = io(API, { auth: { token: R }, transports: ['websocket'] });
  await new Promise((r, f) => { socket.once('connect', r); socket.once('connect_error', f); });
  await api('PATCH', '/repartidor/disponibilidad', { disponible: true }, R);
  await api('PUT', '/repartidor/ubicacion', { latitud: salida.lat, longitud: salida.lng }, R);
  await dormir(3000);
  await api('PATCH', `/repartidor/pedidos/${id}/aceptar`, null, R);
  log('🛵 Repartidor aceptó el pedido');

  // 4) Va al negocio, lo recoge, lo lleva al cliente y lo entrega
  await recorrer(socket, salida, negocio, 'Hacia el negocio');
  await api('PATCH', `/repartidor/pedidos/${id}/recogido`, null, R);
  log('📦 Recogido');
  await dormir(3000);
  await recorrer(socket, negocio, cliente, 'Hacia el cliente');
  await api('PATCH', `/repartidor/pedidos/${id}/entregado`, null, R);
  log('🎉 Entregado: el cliente ya puede confirmarlo y calificar');
  await api('PATCH', '/repartidor/disponibilidad', { disponible: false }, R);
  socket.close();
})().catch((e) => {
  console.error('✘', e.message);
  process.exit(1);
});
