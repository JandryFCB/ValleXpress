const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const Correo = require('../../shared/services/correo.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const { auditar } = require('../../shared/services/log.service');

// REPUTACIÓN del repartidor: lo que dicen de él los clientes y los negocios (1 a 5 estrellas) y las ADVERTENCIAS que
// le manda el administrador cuando su servicio no es bueno (antes de suspenderlo o darlo de baja).
const VIGENTE = "'2999-12-31 00:00:00-05'";
const consulta = (sql, replacements = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT });
const num = (v) => Number(v || 0);

async function exigirRepartidor(usuarioId) {
  const [r] = await consulta(`SELECT cusuario FROM trepartidores WHERE cusuario = :u AND fhasta = ${VIGENTE}`, { u: usuarioId });
  if (!r) throw AppError.notFound('Repartidor no encontrado', 'REPARTIDORNOENCONTRADO');
}

// "completo" = para el administrador (quién calificó); el repartidor ve los comentarios sin el nombre de quien los hizo
async function reputacion(usuarioId, { completo = false } = {}) {
  await exigirRepartidor(usuarioId);
  const [resumen] = await consulta(`
    SELECT COUNT(*) AS total, ROUND(AVG(puntuacion), 2) AS promedio,
           ROUND(AVG(puntuacion) FILTER (WHERE origen = 'CLIENTE'), 2) AS clientes, COUNT(*) FILTER (WHERE origen = 'CLIENTE') AS totalclientes,
           ROUND(AVG(puntuacion) FILTER (WHERE origen = 'NEGOCIO'), 2) AS negocios, COUNT(*) FILTER (WHERE origen = 'NEGOCIO') AS totalnegocios,
           COUNT(*) FILTER (WHERE puntuacion <= 2) AS bajas
      FROM tcalificaciones WHERE destino = 'REPARTIDOR' AND cusuario_repartidor = :u`, { u: usuarioId });
  const ultimas = await consulta(`
    SELECT c.cpedido AS pedido, c.origen, c.puntuacion, c.comentario, c.fcreacion AS fecha,
           p.nombres, p.apellidos, n.nombre AS negocio
      FROM tcalificaciones c
      LEFT JOIN tusuarios u ON u.cusuario = c.cusuario AND u.fhasta = ${VIGENTE}
      LEFT JOIN tpersonas p ON p.cpersona = u.cpersona AND p.fhasta = ${VIGENTE}
      LEFT JOIN tpedidos pe ON pe.cpedido = c.cpedido AND pe.fhasta = ${VIGENTE}
      LEFT JOIN tnegocios n ON n.cnegocio = pe.cnegocio AND n.fhasta = ${VIGENTE}
     WHERE c.destino = 'REPARTIDOR' AND c.cusuario_repartidor = :u
     ORDER BY c.fcreacion DESC LIMIT 50`, { u: usuarioId });
  const advertencias = await consulta(`
    SELECT cadvertencia AS id, motivo, fcreacion AS fecha, cusuario_admin AS admin
      FROM trepartidoradvertencias WHERE cusuario = :u ORDER BY fcreacion DESC`, { u: usuarioId });
  return {
    promedio: num(resumen.promedio),
    total: Number(resumen.total),
    clientes: { promedio: num(resumen.clientes), total: Number(resumen.totalclientes) },
    negocios: { promedio: num(resumen.negocios), total: Number(resumen.totalnegocios) },
    bajas: Number(resumen.bajas),
    calificaciones: ultimas.map((c) => ({
      pedidoId: Number(c.pedido), origen: c.origen.toLowerCase(), puntuacion: c.puntuacion, comentario: c.comentario, fecha: c.fecha,
      ...(completo && { autor: c.origen === 'NEGOCIO' ? c.negocio : [c.nombres, c.apellidos].filter(Boolean).join(' ') || 'Cliente' }),
    })),
    advertencias: advertencias.map((a) => ({ id: Number(a.id), motivo: a.motivo, fecha: a.fecha, ...(completo && { admin: a.admin }) })),
  };
}

// El administrador le advierte: queda registrado, le llega como notificación (push) y por correo
async function advertir(admin, usuarioId, { motivo }, req) {
  await exigirRepartidor(usuarioId);
  const texto = motivo.trim();
  await sequelize.query('INSERT INTO trepartidoradvertencias (cusuario, motivo, cusuario_admin) VALUES (:u, :motivo, :admin)',
    { replacements: { u: usuarioId, motivo: texto, admin: admin.id } });
  const [{ n }] = await consulta('SELECT COUNT(*) AS n FROM trepartidoradvertencias WHERE cusuario = :u', { u: usuarioId });
  const numero = Number(n);
  auditar({ usuarioId: admin.id, accion: 'REPARTIDORADVERTIDO', entidad: 'REPARTIDORES', entidadId: usuarioId, detalle: { motivo: texto, numero }, req });

  const titulo = numero > 1 ? `Advertencia n.º ${numero} sobre tu servicio ⚠️` : 'Advertencia sobre tu servicio ⚠️';
  const cierre = 'Mejora tu servicio: si recibimos más quejas, tu cuenta de repartidor será suspendida o dada de baja.';
  await NotificacionService.notificar({ io: req.io, usuarioId, tipo: 'advertencia_repartidor', titulo, mensaje: `${texto}. ${cierre}` });
  const [u] = await consulta('SELECT email, nombres FROM vusuarios WHERE usuario = :u', { u: usuarioId });
  if (u?.email) {
    Correo.avisoCuenta({
      para: u.email, nombre: u.nombres, asunto: `${titulo} — ValleXpress`, titulo,
      parrafos: [`Hola ${u.nombres}, recibimos quejas sobre tu servicio como repartidor:`, texto, cierre],
      avisoFinal: 'Si crees que es un error, responde este correo y lo revisamos.',
    });
  }
  return reputacion(usuarioId, { completo: true });
}

module.exports = { reputacion, advertir };
