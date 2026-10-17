const Notificacion = require('./notificacion.model');
const Dispositivo = require('./dispositivo.model');
const { enviarPush } = require('../../services/fcm.service');
const AppError = require('../../shared/errors/AppError');
const { logMensaje } = require('../../shared/services/log.service');

// Notificaciones de la app: se guardan en la BD (lista de avisos), se emiten por socket al celular que está
// conectado (sala "user:<usuario>") y se envían como push (Firebase) a los dispositivos registrados.

const aApi = (n) => ({
  id: Number(n.id),
  tipo: n.tipo,
  titulo: n.titulo,
  mensaje: n.mensaje,
  pedidoId: n.pedidoId == null ? null : Number(n.pedidoId),
  datos: n.datos || {},
  leida: n.leida,
  fecha: n.creadoEn,
});

async function listar(usuarioId, { limite = 50, pagina = 1 } = {}) {
  const tope = Math.min(Number(limite) || 50, 100);
  const salto = (Math.max(Number(pagina) || 1, 1) - 1) * tope;
  const { rows, count } = await Notificacion.findAndCountAll({ where: { usuarioId }, order: [['creadoEn', 'DESC'], ['id', 'DESC']], limit: tope, offset: salto });
  const noLeidas = await Notificacion.count({ where: { usuarioId, leida: false } });
  return { notificaciones: rows.map(aApi), total: count, noLeidas, hayMas: salto + rows.length < count };
}

const noLeidas = async (usuarioId) => ({ noLeidas: await Notificacion.count({ where: { usuarioId, leida: false } }) });

async function marcarLeida(usuarioId, id) {
  const [cambiadas] = await Notificacion.update({ leida: true, leidaEn: new Date() }, { where: { id, usuarioId } });
  if (!cambiadas) throw AppError.notFound('Notificación no encontrada', 'NOTIFICACIONNOENCONTRADA');   // ajena o inexistente: mismo error
}

async function marcarTodas(usuarioId) {
  const [cambiadas] = await Notificacion.update({ leida: true, leidaEn: new Date() }, { where: { usuarioId, leida: false } });
  return { marcadas: cambiadas };
}

// Registra (o reasigna) el token de Firebase del celular. Un token pertenece a un solo usuario a la vez.
async function registrarDispositivo(usuarioId, { token, plataforma, modelo, appVer }) {
  const datos = { usuarioId, plataforma: String(plataforma || 'android').toUpperCase(), modelo: modelo || null, versionApp: appVer || null, activo: true, ultimoUso: new Date() };
  const existente = await Dispositivo.findOne({ where: { tokenFcm: token } });
  if (existente) await existente.update(datos);
  else await Dispositivo.create({ ...datos, tokenFcm: token });
}

// Al cerrar sesión: ese celular deja de recibir los avisos de esta cuenta
async function quitarDispositivo(usuarioId, token) {
  await Dispositivo.destroy({ where: { tokenFcm: token, usuarioId } });
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
// debe tumbar la operación que la originó (queda registrada en TLOGMENSAJES).
async function notificar({ io, usuarioId, tipo, titulo, mensaje, pedidoId = null, datos = {} }) {
  if (!usuarioId) return;
  try {
    const n = await Notificacion.create({ usuarioId, tipo, titulo, mensaje, pedidoId, datos });
    if (io) io.to(`user:${usuarioId}`).emit('notificacion', aApi(n));
    enviarAlCelular(usuarioId, titulo, mensaje, { tipo, pedidoId, ...datos }).catch(() => {});
  } catch (e) {
    logMensaje({ nivel: 'ADVERTENCIA', modulo: 'NOTIFICACIONES', accion: 'NOTIFICACIONFALLIDA', mensaje: 'No se pudo crear la notificación', detalle: { tipo, error: e.message }, usuarioId, pedidoId });
  }
}

// El mismo aviso a todos los administradores activos (comprobantes por revisar, pedidos sin repartidor...)
async function notificarAdministradores(aviso) {
  const UsuarioCuenta = require('../auth/usuarioCuenta.model');       // perezoso: evita una dependencia circular
  const { ROLES } = require('../../shared/constants/codigos');
  const admins = await UsuarioCuenta.findAll({ where: { rol: ROLES.ADMINISTRADOR, estatus: '001' }, attributes: ['id'] });
  for (const a of admins) await notificar({ ...aviso, usuarioId: a.id });
}

module.exports = { listar, noLeidas, marcarLeida, marcarTodas, registrarDispositivo, quitarDispositivo, notificar, notificarAdministradores };
