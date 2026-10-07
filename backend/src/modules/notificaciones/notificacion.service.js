const Notificacion = require('./notificacion.model');
const Dispositivo = require('./dispositivo.model');
const { enviarPush } = require('../../services/fcm.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const { logMensaje } = require('../../shared/services/log.service');

// Notificaciones de la app: se guardan en la BD (lista de notificaciones), se emiten por socket al celular que
// está conectado (sala "user:<usuario>") y se envían como push (Firebase) a los dispositivos registrados.

const aApi = (n) => ({
  id: Number(n.id),
  usuarioId: n.usuarioId,
  titulo: n.titulo,
  mensaje: n.mensaje,
  tipo: n.tipo,
  leida: n.leida,
  pedidoId: n.pedidoId,
  createdAt: n.creadoEn,
});

async function listar(usuarioId, { limite = 100, pagina = 1 } = {}) {
  const tope = Math.min(Number(limite) || 100, 200);
  const salto = (Math.max(Number(pagina) || 1, 1) - 1) * tope;
  const { rows, count } = await Notificacion.findAndCountAll({
    where: { usuarioId }, order: [['creadoEn', 'DESC']], limit: tope, offset: salto,
  });
  const noLeidas = await Notificacion.count({ where: { usuarioId, leida: false } });
  return { notificaciones: rows.map(aApi), total: count, noLeidas };
}

async function marcarLeida(usuarioId, id) {
  const n = await Notificacion.findOne({ where: { id, usuarioId } });
  if (!n) throw AppError.notFound('Notificación no encontrada', 'NOTIFICACIONNOENCONTRADA');   // ajena o inexistente: mismo error
  await withTransaction((t) => n.update({ leida: true, leidaEn: new Date(), actualizadoPor: usuarioId }, { transaction: t }), { usuarioId });
}

// Registra (o reasigna) el token de Firebase del celular. Un token pertenece a un solo usuario a la vez.
async function registrarDispositivo(usuarioId, { token, plataforma, modelo, appVer }) {
  const datos = { usuarioId, plataforma: String(plataforma || 'android').toUpperCase(), modelo, appVer, activo: true, ultimoUsoEn: new Date(), actualizadoPor: usuarioId };
  await withTransaction(async (t) => {
    const existente = await Dispositivo.findOne({ where: { tokenFcm: token }, paranoid: false, transaction: t });
    if (!existente) return Dispositivo.create({ ...datos, tokenFcm: token, creadoPor: usuarioId }, { transaction: t });
    if (existente.eliminadoEn) await existente.restore({ transaction: t });
    return existente.update(datos, { transaction: t });
  }, { usuarioId });
}

async function quitarDispositivo(usuarioId, token) {
  const d = await Dispositivo.findOne({ where: { tokenFcm: token, usuarioId } });
  if (d) await withTransaction((t) => d.destroy({ transaction: t }), { usuarioId });
}

const textoPlano = (datos) => Object.fromEntries(Object.entries(datos).filter(([, v]) => v != null).map(([k, v]) => [k, String(v)]));

// Push a todos los celulares del usuario. Si Firebase dice que un token ya no existe, se desactiva.
async function enviarAlCelular(usuarioId, titulo, mensaje, datos) {
  const dispositivos = await Dispositivo.findAll({ where: { usuarioId, activo: true } });
  for (const d of dispositivos) {
    const r = await enviarPush(d.tokenFcm, titulo, mensaje, textoPlano(datos));
    if (r.invalido) await d.update({ activo: false });
    else if (!r.ok && !r.omitido) {
      logMensaje({ nivel: 'ADVERTENCIA', modulo: 'FCM', accion: 'PUSHFALLIDO', mensaje: 'No se pudo enviar la notificación push', detalle: { error: r.error }, usuarioId });
    }
  }
}

// Crea la notificación, la emite por socket y la envía como push. NUNCA lanza error: una notificación fallida no
// debe tumbar la operación que la originó (queda registrada en LOGMENSAJES).
//   guardar:false -> solo socket/push (sin fila en la lista de notificaciones)
async function notificar({ io, usuarioId, tipo, titulo, mensaje, pedidoId = null, estado = null, extra = {}, guardar = true }) {
  try {
    if (guardar) await Notificacion.create({ usuarioId, tipo, titulo, mensaje, pedidoId, canal: 'APP', datos: { estado, ...extra } });
    if (io) io.to(`user:${usuarioId}`).emit('notificacion', { title: titulo, message: mensaje, tipo, pedidoId, ...(estado && { estado }), ...extra, ts: Date.now() });
    enviarAlCelular(usuarioId, titulo, mensaje, { tipo, pedidoId, estado, ...extra }).catch(() => {});
  } catch (e) {
    logMensaje({ nivel: 'ADVERTENCIA', modulo: 'NOTIFICACIONES', accion: 'NOTIFICACIONFALLIDA', mensaje: 'No se pudo crear la notificación', detalle: { tipo, error: e.message }, usuarioId, pedidoId });
  }
}

module.exports = { listar, marcarLeida, registrarDispositivo, quitarDispositivo, notificar };
