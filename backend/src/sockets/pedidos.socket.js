// src/sockets/pedidos.socket.js
const Pedido = require('../models/Pedido');
const Usuario = require('../models/Usuario');
const Vendedor = require('../models/Vendedor');
const Repartidor = require('../models/Repartidor');

function roomPedido(pedidoId) {
  return `pedido:${pedidoId}`;
}

// Cache en memoria: última ubicación por pedido
// (Si reinicias el backend se pierde, pero para MVP está perfecto)
const ultimaUbicacionPorPedido = new Map();

/**
 * Valida si un usuario (por JWT) tiene permiso para un pedido.
 * Permite:
 * - cliente dueño
 * - vendedor dueño
 * - repartidor asignado
 */
async function puedeAccederPedido({ pedidoId, usuarioId, tipoUsuario }) {
  const pedido = await Pedido.findByPk(pedidoId, {
    include: [
      {
        model: Usuario,
        as: 'cliente',
        attributes: ['id'],
      },
      {
        model: Vendedor,
        as: 'vendedor',
        include: [{ model: Usuario, as: 'usuario', attributes: ['id'] }],
      },
      {
        model: Repartidor,
        as: 'repartidor',
        required: false,
        include: [{ model: Usuario, as: 'usuario', attributes: ['id'] }],
      },
    ],
  });

  if (!pedido) return { ok: false, motivo: 'PEDIDO_NO_EXISTE' };

  const clienteUserId = pedido.cliente?.id;
  const vendedorUserId = pedido.vendedor?.usuario?.id;
  const repartidorUserId = pedido.repartidor?.usuario?.id;

  const esClienteDueno = tipoUsuario === 'cliente' && clienteUserId === usuarioId;
  const esVendedorDueno = tipoUsuario === 'vendedor' && vendedorUserId === usuarioId;
  const esRepartidorAsignado =
    tipoUsuario === 'repartidor' &&
    repartidorUserId &&
    repartidorUserId === usuarioId;

  if (esClienteDueno || esVendedorDueno || esRepartidorAsignado) {
    return { ok: true, pedido, esRepartidorAsignado };
  }

  return { ok: false, motivo: 'NO_AUTORIZADO' };
}

module.exports = function registerPedidosSocket(io, socket) {
  // Para evitar spam de ubicaciones por socket
  let lastLocationTs = 0;

  // =========================
  // pedido:join
  // =========================
  socket.on('pedido:join', async (payload, ack) => {
    try {
      const pedidoId = payload?.pedidoId;
      if (!pedidoId) return ack?.({ ok: false, error: 'PEDIDO_ID_REQUERIDO' });

      const usuarioId = socket.usuario?.id;
      const tipoUsuario = socket.usuario?.tipoUsuario;

      if (!usuarioId || !tipoUsuario) {
        return ack?.({ ok: false, error: 'USUARIO_NO_AUTENTICADO' });
      }

      const acceso = await puedeAccederPedido({ pedidoId, usuarioId, tipoUsuario });
      if (!acceso.ok) return ack?.({ ok: false, error: acceso.motivo });

      socket.join(roomPedido(pedidoId));

      // Si hay última ubicación cacheada, envíala al que se une
      const last = ultimaUbicacionPorPedido.get(String(pedidoId));
      if (last) {
        socket.emit('pedido:ubicacion', {
          pedidoId,
          ...last,
          source: 'cache',
        });
      }

      // opcional: notificar que alguien se unió (registro más seguro)
      if (process.env.NODE_ENV === 'development') {
        console.log('📡 pedido joined =>', roomPedido(pedidoId), { pedidoId, usuarioId, tipoUsuario });
      }

      io.to(roomPedido(pedidoId)).emit('pedido:joined', {
        pedidoId,
        usuarioId,
        tipoUsuario,
        ts: Date.now(),
      });

      return ack?.({ ok: true, room: roomPedido(pedidoId) });
    } catch (err) {
      console.error('❌ pedido:join error', err);
      return ack?.({ ok: false, error: 'ERROR_PEDIDO_JOIN' });
    }
  });

  // =========================
  // pedido:leave (opcional)
  // =========================
  socket.on('pedido:leave', (payload, ack) => {
    const pedidoId = payload?.pedidoId;
    if (!pedidoId) return ack?.({ ok: false, error: 'PEDIDO_ID_REQUERIDO' });

    socket.leave(roomPedido(pedidoId));
    return ack?.({ ok: true });
  });

  // =========================
  // repartidor:ubicacion
  // (emitido por app repartidor)
  // =========================
    socket.on('repartidor:ubicacion', async (payload, ack) => {
    try {
        // Debug: mostrar info del socket para verificar rol del remitente (solo en dev)
        try {
          if (process.env.NODE_ENV === 'development') {
            console.log('📡 repartidor:ubicacion recibido desde socket.usuario =>', {
              id: socket.usuario?.id,
              tipoUsuario: socket.usuario?.tipoUsuario,
            });
          }
        } catch (_) {}
      const usuarioId = socket.usuario?.id;
      const tipoUsuario = socket.usuario?.tipoUsuario;

      if (tipoUsuario !== 'repartidor') {
          console.warn('⚠️ repartidor:ubicacion rechazado - tipoUsuario no es repartidor', { tipoUsuario, usuarioId });
          return ack?.({ ok: false, error: 'SOLO_REPARTIDOR' });
      }

      // anti-spam: 1 update cada 2s
      const now = Date.now();
      if (now - lastLocationTs < 2000) {
        return ack?.({ ok: false, error: 'MUY_FRECUENTE_2S' });
      }
      lastLocationTs = now;

      const pedidoId = payload?.pedidoId;
      const latNum = Number(payload?.lat);
      const lngNum = Number(payload?.lng);

      if (!pedidoId) return ack?.({ ok: false, error: 'PEDIDO_ID_REQUERIDO' });

      const latLngOk =
        Number.isFinite(latNum) &&
        Number.isFinite(lngNum) &&
        latNum >= -90 &&
        latNum <= 90 &&
        lngNum >= -180 &&
        lngNum <= 180;

      if (!latLngOk) return ack?.({ ok: false, error: 'LATLNG_INVALIDO' });

      // Seguridad: el repartidor solo puede emitir si ES el asignado al pedido
      const acceso = await puedeAccederPedido({ pedidoId, usuarioId, tipoUsuario });
      if (!acceso.ok) return ack?.({ ok: false, error: acceso.motivo });

      // Extra seguridad: debe ser repartidor asignado (no solo "acceso")
      if (!acceso.esRepartidorAsignado) {
        return ack?.({ ok: false, error: 'REPARTIDOR_NO_ASIGNADO' });
      }

      // Asegurar join (por si no lo hizo antes)
      socket.join(roomPedido(pedidoId));

      const data = {
        lat: latNum,
        lng: lngNum,
        heading: payload?.heading != null ? Number(payload.heading) : null,
        speed: payload?.speed != null ? Number(payload.speed) : null,
        accuracy: payload?.accuracy != null ? Number(payload.accuracy) : null,
        ts: payload?.ts != null ? Number(payload.ts) : now,
        repartidorUsuarioId: usuarioId,
      };

      // cache última ubicación
      ultimaUbicacionPorPedido.set(String(pedidoId), data);

      // broadcast a los que ven el pedido
      try {
        if (process.env.NODE_ENV === 'development') {
          console.log('📣 Emitting pedido:ubicacion =>', {
            room: roomPedido(pedidoId),
            payload: { pedidoId, ...data, source: 'live' },
          });
        }
      } catch (_) {}
      io.to(roomPedido(pedidoId)).emit('pedido:ubicacion', {
        pedidoId,
        ...data,
        source: 'live',
      });

      return ack?.({ ok: true });
    } catch (err) {
      console.error('❌ repartidor:ubicacion error', err);
      return ack?.({ ok: false, error: 'ERROR_REPARTIDOR_UBICACION' });
    }
  });
};
