const RepartidorService = require('./repartidor.service');

// Ubicación en vivo del repartidor por Socket.IO:
//   app del repartidor -> servidor:  'repartidor:ubicacion' { lat, lng, precision?, velocidad? (m/s), rumbo? }  (con ack)
//   servidor -> cliente y negocio:   'pedido:ubicacion' { pedidoId, latitud, longitud, rumbo, velocidadKmh, fecha }
// Solo cuenta para las entregas EN CURSO del propio repartidor (el servicio busca cuáles son); nadie más recibe su
// posición. Máximo un envío cada 2 segundos por conexión.
const MINIMOMS = 2000;

module.exports = function registrarUbicacionSocket(io, socket) {
  let ultimo = 0;
  socket.on('repartidor:ubicacion', async (datos, ack) => {
    const responder = typeof ack === 'function' ? ack : () => {};
    try {
      if (socket.usuario?.tipoUsuario !== 'repartidor') return responder({ ok: false, error: 'SOLOREPARTIDOR' });
      const ahora = Date.now();
      if (ahora - ultimo < MINIMOMS) return responder({ ok: false, error: 'MUYFRECUENTE' });
      const lat = Number(datos?.lat);
      const lng = Number(datos?.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return responder({ ok: false, error: 'UBICACIONINVALIDA' });
      ultimo = ahora;
      const opcional = (v) => (v == null || !Number.isFinite(Number(v)) ? null : Number(v));
      const r = await RepartidorService.registrarUbicacion(socket.usuario.id, {
        lat, lng, precision: opcional(datos.precision), velocidad: opcional(datos.velocidad), rumbo: opcional(datos.rumbo),
      }, io);
      return responder({ ok: true, ...r });
    } catch (e) {
      return responder({ ok: false, error: 'ERRORUBICACION' });
    }
  });
};
