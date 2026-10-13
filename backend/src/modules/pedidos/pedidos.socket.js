const Pedido = require('./pedido.model');
const Usuario = require('../auth/usuario.model');
const Vendedor = require('../vendedores/vendedor.model');
const Repartidor = require('../repartidores/repartidor.model');
const { sequelize } = require('../../config/database');
const { logMensaje } = require('../../shared/services/log.service');

// Seguimiento del pedido en tiempo real (Socket.IO). Eventos:
//   cliente -> servidor:  pedido:join { pedidoId } · pedido:leave { pedidoId } · repartidor:ubicacion { pedidoId, lat, lng, ... }
//   servidor -> cliente:  pedido:joined · pedido:ubicacion
// Solo entra a la sala de un pedido su cliente, su vendedor o su repartidor asignado.

const roomPedido = (pedidoId) => `pedido:${pedidoId}`;

// Última ubicación por pedido (para quien se une tarde). Caduca a las 6 horas para no crecer sin límite.
const TTLMS = 6 * 60 * 60 * 1000;
const ultimaUbicacionPorPedido = new Map();
function recordarUbicacion(pedidoId, data) {
  const ahora = Date.now();
  ultimaUbicacionPorPedido.set(String(pedidoId), { data, guardadoEn: ahora });
  if (ultimaUbicacionPorPedido.size > 500) {
    for (const [k, v] of ultimaUbicacionPorPedido) if (ahora - v.guardadoEn > TTLMS) ultimaUbicacionPorPedido.delete(k);
  }
}
const ubicacionReciente = (pedidoId) => {
  const v = ultimaUbicacionPorPedido.get(String(pedidoId));
  return v && Date.now() - v.guardadoEn <= TTLMS ? v.data : null;
};

// La ubicación del repartidor se guarda en la BD como máximo cada 15 segundos por pedido (historial + posición actual)
const INTERVALOGUARDADO = 15 * 1000;
const ultimoGuardado = new Map();
async function guardarUbicacion(pedido, data) {
  const ahora = Date.now();
  if (ahora - (ultimoGuardado.get(pedido.id) || 0) < INTERVALOGUARDADO) return;
  ultimoGuardado.set(pedido.id, ahora);
  try {
    await Repartidor.update({ latitud: data.lat, longitud: data.lng, ubicacionEn: new Date() }, { where: { id: pedido.repartidorId } });
    await sequelize.query(
      `INSERT INTO tubicacionrepartidor (repartidor, cpedido, latitud, longitud, precisionm, velocidadkmh, rumbo)
       VALUES (:repartidor, :pedido, :lat, :lng, :precision, :velocidad, :rumbo)`,
      { replacements: { repartidor: pedido.repartidorId, pedido: pedido.id, lat: data.lat, lng: data.lng, precision: data.accuracy, velocidad: data.speed != null ? data.speed * 3.6 : null, rumbo: data.heading } },
    );
  } catch (e) {
    logMensaje({ nivel: 'ADVERTENCIA', modulo: 'SOCKET', accion: 'UBICACIONNOGUARDADA', mensaje: 'No se pudo guardar la ubicación del repartidor', detalle: { error: e.message }, pedidoId: pedido.id });
  }
}

// ¿Tiene este usuario permiso sobre el pedido? Cliente dueño, vendedor dueño o repartidor asignado.
async function puedeAccederPedido({ pedidoId, usuarioId, tipoUsuario }) {
  const pedido = await Pedido.findByPk(pedidoId, {
    include: [
      { model: Usuario, as: 'cliente', attributes: ['id'] },
      { model: Vendedor, as: 'vendedor', include: [{ model: Usuario, as: 'usuario', attributes: ['id'] }] },
      { model: Repartidor, as: 'repartidor', required: false, include: [{ model: Usuario, as: 'usuario', attributes: ['id'] }] },
    ],
  });
  if (!pedido) return { ok: false, motivo: 'PEDIDO_NO_EXISTE' };

  const esClienteDueno = tipoUsuario === 'cliente' && pedido.cliente?.id === usuarioId;
  const esVendedorDueno = tipoUsuario === 'vendedor' && pedido.vendedor?.usuario?.id === usuarioId;
  const esRepartidorAsignado = tipoUsuario === 'repartidor' && !!pedido.repartidor?.usuario?.id && pedido.repartidor.usuario.id === usuarioId;
  if (esClienteDueno || esVendedorDueno || esRepartidorAsignado) return { ok: true, pedido, esRepartidorAsignado };
  return { ok: false, motivo: 'NO_AUTORIZADO' };
}

module.exports = function registerPedidosSocket(io, socket) {
  let lastLocationTs = 0;

  socket.on('pedido:join', async (payload, ack) => {
    try {
      const pedidoId = payload?.pedidoId;
      if (!pedidoId) return ack?.({ ok: false, error: 'PEDIDO_ID_REQUERIDO' });
      const usuarioId = socket.usuario?.id;
      const tipoUsuario = socket.usuario?.tipoUsuario;
      if (!usuarioId || !tipoUsuario) return ack?.({ ok: false, error: 'USUARIO_NO_AUTENTICADO' });

      const acceso = await puedeAccederPedido({ pedidoId, usuarioId, tipoUsuario });
      if (!acceso.ok) return ack?.({ ok: false, error: acceso.motivo });

      socket.join(roomPedido(pedidoId));
      const last = ubicacionReciente(pedidoId);
      if (last) socket.emit('pedido:ubicacion', { pedidoId, ...last, source: 'cache' });
      io.to(roomPedido(pedidoId)).emit('pedido:joined', { pedidoId, usuarioId, tipoUsuario, ts: Date.now() });
      return ack?.({ ok: true, room: roomPedido(pedidoId) });
    } catch (err) {
      return ack?.({ ok: false, error: 'ERROR_PEDIDO_JOIN' });
    }
  });

  socket.on('pedido:leave', (payload, ack) => {
    const pedidoId = payload?.pedidoId;
    if (!pedidoId) return ack?.({ ok: false, error: 'PEDIDO_ID_REQUERIDO' });
    socket.leave(roomPedido(pedidoId));
    return ack?.({ ok: true });
  });

  socket.on('repartidor:ubicacion', async (payload, ack) => {
    try {
      const usuarioId = socket.usuario?.id;
      const tipoUsuario = socket.usuario?.tipoUsuario;
      if (tipoUsuario !== 'repartidor') return ack?.({ ok: false, error: 'SOLO_REPARTIDOR' });

      const now = Date.now();
      if (now - lastLocationTs < 2000) return ack?.({ ok: false, error: 'MUY_FRECUENTE_2S' });
      lastLocationTs = now;

      const pedidoId = payload?.pedidoId;
      if (!pedidoId) return ack?.({ ok: false, error: 'PEDIDO_ID_REQUERIDO' });
      const lat = Number(payload?.lat);
      const lng = Number(payload?.lng);
      const valido = Number.isFinite(lat) && Number.isFinite(lng) && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
      if (!valido) return ack?.({ ok: false, error: 'LATLNG_INVALIDO' });

      const acceso = await puedeAccederPedido({ pedidoId, usuarioId, tipoUsuario });
      if (!acceso.ok) return ack?.({ ok: false, error: acceso.motivo });     // para un repartidor, "ok" implica que es el asignado

      socket.join(roomPedido(pedidoId));
      const data = {
        lat,
        lng,
        heading: payload?.heading != null ? Number(payload.heading) : null,
        speed: payload?.speed != null ? Number(payload.speed) : null,        // m/s (como lo entrega el GPS del celular)
        accuracy: payload?.accuracy != null ? Number(payload.accuracy) : null,
        ts: payload?.ts != null ? Number(payload.ts) : now,
        repartidorUsuarioId: usuarioId,
      };
      recordarUbicacion(pedidoId, data);
      io.to(roomPedido(pedidoId)).emit('pedido:ubicacion', { pedidoId, ...data, source: 'live' });
      guardarUbicacion(acceso.pedido, data);                                  // sin esperar: no frena el seguimiento en vivo
      return ack?.({ ok: true });
    } catch (err) {
      return ack?.({ ok: false, error: 'ERROR_REPARTIDOR_UBICACION' });
    }
  });
};
