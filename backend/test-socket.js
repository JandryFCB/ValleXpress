const { io } = require("socket.io-client");
const fs = require("fs");
const path = require("path");

// Simple arg parser: --key value
function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i++) {
    const k = args[i];
    if (k.startsWith("--")) {
      const key = k.replace(/^--/, "");
      const val = args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : true;
      if (val !== true) i++;
      out[key] = val;
    }
  }
  return out;
}

const a = parseArgs();

// ===== CONFIG (CLI/env/file) =====
// Permite cargar desde --config o SOCKET_CONFIG (JSON con {url, clientToken, driverToken, pedidoId})
let cfg = {};
try {
  const cfgPath = a.config || process.env.SOCKET_CONFIG;
  if (cfgPath) {
    const resolved = path.resolve(cfgPath);
    cfg = JSON.parse(fs.readFileSync(resolved, "utf8"));
    console.log("📝 Cargando configuración desde:", resolved);
  }
} catch (e) {
  console.warn("No se pudo leer config:", e.message || e);
}

// Preferir flags CLI; luego archivo de config; luego env; luego defaults
const URL = a.url || cfg.url || process.env.SOCKET_URL || "http://localhost:3000";

const TOKEN_CLIENTE =
  a["client-token"] ||
  cfg.clientToken ||
  process.env.CLIENT_TOKEN ||
  "PEGAR_TOKEN_CLIENTE_AQUI";

const TOKEN_REPARTIDOR =
  a["driver-token"] ||
  cfg.driverToken ||
  process.env.DRIVER_TOKEN ||
  "PEGAR_TOKEN_REPARTIDOR_AQUI";

const PEDIDO_ID =
  a["pedido-id"] ||
  cfg.pedidoId ||
  process.env.PEDIDO_ID ||
  "PEGAR_UUID_PEDIDO_AQUI";

// Coordenadas opcionales (o usa dummy válidos)
const LAT = Number(a.lat || cfg.lat || process.env.TEST_LAT || -3.9931);
const LNG = Number(a.lng || cfg.lng || process.env.TEST_LNG || -79.2042);

// ===== Validación básica =====
if (
  !TOKEN_CLIENTE ||
  TOKEN_CLIENTE.startsWith("PEGAR_TOKEN") ||
  !TOKEN_REPARTIDOR ||
  TOKEN_REPARTIDOR.startsWith("PEGAR_TOKEN") ||
  !PEDIDO_ID ||
  PEDIDO_ID.startsWith("PEGAR_UUID")
) {
  console.log("Uso:");
  console.log('  node backend/test-socket.js --url http://localhost:3000 --client-token "<JWT_CLIENTE>" --driver-token "<JWT_REPARTIDOR>" --pedido-id "<UUID>" [--lat -3.99 --lng -79.20]');
  console.log("O variables de entorno: SOCKET_URL, CLIENT_TOKEN, DRIVER_TOKEN, PEDIDO_ID, TEST_LAT, TEST_LNG");
  process.exit(1);
}

// =====================
// SOCKET CLIENTE (escucha)
// =====================
const cliente = io(URL, {
  auth: { token: TOKEN_CLIENTE },
  transports: ["websocket"],
});

cliente.on("connect", () => {
  console.log("✅ CLIENTE conectado:", cliente.id);

  cliente.emit("pedido:join", { pedidoId: PEDIDO_ID }, (ack) => {
    console.log("CLIENTE join ack:", ack);
  });
});

cliente.on("pedido:ubicacion", (data) => {
  console.log("📍 CLIENTE recibe ubicacion:", data);
});

cliente.on("connect_error", (e) => {
  console.log("❌ CLIENTE connect_error:", e.message || e);
});
cliente.on("disconnect", (reason) => {
  console.log("🔴 CLIENTE disconnect:", reason);
});

// =====================
// SOCKET REPARTIDOR (emite)
// =====================
const repartidor = io(URL, {
  auth: { token: TOKEN_REPARTIDOR },
  transports: ["websocket"],
});

repartidor.on("connect", () => {
  console.log("✅ REPARTIDOR conectado:", repartidor.id);

  repartidor.emit("pedido:join", { pedidoId: PEDIDO_ID }, (ack) => {
    console.log("REPARTIDOR join ack:", ack);
  });

  // Simular ubicación cada 3s (respeta anti-spam 2s en backend)
  setInterval(() => {
    repartidor.emit(
      "repartidor:ubicacion",
      {
        pedidoId: PEDIDO_ID,
        lat: LAT,
        lng: LNG,
        heading: 90,
        speed: 5,
        accuracy: 10,
        ts: Date.now(),
      },
      (ack) => {
        console.log("REPARTIDOR ubic ack:", ack);
      }
    );
  }, 3000);
});

repartidor.on("connect_error", (e) => {
  console.log("❌ REPARTIDOR connect_error:", e.message || e);
});
repartidor.on("disconnect", (reason) => {
  console.log("🔴 REPARTIDOR disconnect:", reason);
});
