const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const { auditar } = require('../../shared/services/log.service');
const { VEHICULOSINPLACA, APROBACION, APROBACIONAAPI } = require('../../shared/constants/codigos');

// DOCUMENTOS DEL REPARTIDOR: fotos para verificar su identidad y su vehículo antes de aprobarlo.
//   * Siempre: cédula (frente y reverso) y una selfie sosteniendo la cédula.
//   * Con vehículo de placa (moto, auto, camioneta): además la licencia y la matrícula.
// Se guarda una foto vigente por tipo (subir otra la reemplaza). El administrador las ve en la aprobación.

const DOCUMENTOS = [
  { tipo: 'cedula_frente', codigo: 'CEDULAFRENTE', titulo: 'Cédula (frente)', ayuda: 'Que se lean tu nombre, tu número y tu foto', siempre: true },
  { tipo: 'cedula_reverso', codigo: 'CEDULAREVERSO', titulo: 'Cédula (reverso)', ayuda: 'La parte de atrás completa', siempre: true },
  { tipo: 'selfie', codigo: 'SELFIE', titulo: 'Selfie con tu cédula', ayuda: 'Tu cara y la cédula junto a ella, con buena luz', siempre: true },
  { tipo: 'licencia', codigo: 'LICENCIA', titulo: 'Licencia de conducir', ayuda: 'Vigente y del tipo de tu vehículo', siempre: false },
  { tipo: 'matricula', codigo: 'MATRICULA', titulo: 'Matrícula del vehículo', ayuda: 'Que coincida la placa que registraste', siempre: false },
];
const TIPOS = DOCUMENTOS.map((d) => d.tipo);
const DECODIGO = Object.fromEntries(DOCUMENTOS.map((d) => [d.codigo, d]));

const consulta = (sql, replacements, opciones = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT, ...opciones });

// Qué documentos pide según el vehículo (código TTIPOSVEHICULO)
const requeridosPara = (vehiculo) => DOCUMENTOS.filter((d) => d.siempre || !VEHICULOSINPLACA.includes(vehiculo));

async function vehiculoDe(usuarioId) {
  const [r] = await consulta("SELECT ctipovehiculo AS vehiculo FROM trepartidores WHERE cusuario = :u AND fhasta = '2999-12-31 00:00:00-05'", { u: usuarioId });
  if (!r) throw AppError.notFound('Primero registra tu vehículo', 'REPARTIDORNOENCONTRADO');
  return r.vehiculo;
}

// Lista de documentos del repartidor con su foto (si ya la subió)
async function documentos(usuarioId, req) {
  const requeridos = requeridosPara(await vehiculoDe(usuarioId));
  const [estado] = await consulta("SELECT cestatusaprobacion AS aprobacion FROM trepartidores WHERE cusuario = :u AND fhasta = '2999-12-31 00:00:00-05'", { u: usuarioId });
  const filas = await consulta('SELECT tipo, carchivo, fsubido FROM trepartidordocumentos WHERE cusuario = :u', { u: usuarioId });
  const urls = await ArchivoService.mapaUrls(req, filas.map((f) => f.carchivo));
  const porCodigo = Object.fromEntries(filas.map((f) => [f.tipo, f]));
  const lista = requeridos.map((d) => {
    const f = porCodigo[d.codigo];
    const url = f && urls[String(f.carchivo)];
    return { tipo: d.tipo, titulo: d.titulo, ayuda: d.ayuda, subido: !!f, ...(url && { url: url.url, miniatura: url.miniatura, fecha: f.fsubido }) };
  });
  return { documentos: lista, completos: lista.every((d) => d.subido), faltan: lista.filter((d) => !d.subido).length, aprobacion: APROBACIONAAPI[estado?.aprobacion] || 'pendiente' };
}

// Cuántos documentos subió cada repartidor y cuántos le piden (para la lista de aprobaciones del admin)
async function resumenDe(repartidores) {
  if (!repartidores.length) return {};
  const filas = await consulta('SELECT cusuario, tipo FROM trepartidordocumentos WHERE cusuario IN (:u)', { u: repartidores.map((r) => r.usuarioId) });
  return Object.fromEntries(repartidores.map((r) => {
    const requeridos = requeridosPara(r.vehiculo).map((d) => d.codigo);
    const subidos = filas.filter((f) => f.cusuario === r.usuarioId && requeridos.includes(f.tipo)).length;
    return [r.usuarioId, { subidos, requeridos: requeridos.length }];
  }));
}

async function subir(usuarioId, tipo, imagen, req) {
  const doc = DOCUMENTOS.find((d) => d.tipo === tipo);
  if (!doc) throw AppError.badRequest('Ese documento no existe', 'DOCUMENTOINVALIDO');
  const vehiculo = await vehiculoDe(usuarioId);
  if (!requeridosPara(vehiculo).includes(doc)) throw AppError.badRequest('Ese documento no se pide para tu vehículo', 'DOCUMENTONOREQUERIDO');
  const antes = await documentos(usuarioId, req);

  await withTransaction(async (t) => {
    const archivo = await ArchivoService.guardarBase64({ base64: imagen, categoria: 'DOCUMENTO', propietario: usuarioId, nombreOriginal: `repartidor-${tipo}` }, { transaction: t });
    await sequelize.query(
      `INSERT INTO trepartidordocumentos (cusuario, tipo, carchivo) VALUES (:u, :tipo, :archivo)
       ON CONFLICT (cusuario, tipo) DO UPDATE SET carchivo = EXCLUDED.carchivo, fsubido = clock_timestamp()`,
      { replacements: { u: usuarioId, tipo: doc.codigo, archivo: archivo.id }, transaction: t },
    );
  }, { usuarioId });
  auditar({ usuarioId, accion: 'DOCUMENTOSUBIDO', entidad: 'REPARTIDORES', entidadId: usuarioId, detalle: { tipo }, req });

  const ahora = await documentos(usuarioId, req);
  // Recién completos y esperando revisión: se avisa a los administradores
  if (!antes.completos && ahora.completos) {
    const [r] = await consulta("SELECT cestatusaprobacion AS aprobacion FROM trepartidores WHERE cusuario = :u AND fhasta = '2999-12-31 00:00:00-05'", { u: usuarioId });
    if (r?.aprobacion === APROBACION.PENDIENTE) {
      await NotificacionService.notificarAdministradores({
        io: req.io, tipo: 'repartidor_documentos', titulo: 'Repartidor listo para revisar 🪪',
        mensaje: `${usuarioId} subió todos sus documentos. Revísalos en Gestión → Repartidores`,
      });
    }
  }
  return ahora;
}

// Al eliminar la cuenta: los códigos de archivo de sus documentos (para borrarlos) y se quitan las filas
async function quitarTodos(usuarioId, opciones = {}) {
  const filas = await consulta('SELECT carchivo FROM trepartidordocumentos WHERE cusuario = :u', { u: usuarioId }, opciones);
  await sequelize.query('DELETE FROM trepartidordocumentos WHERE cusuario = :u', { replacements: { u: usuarioId }, ...opciones });
  return filas.map((f) => Number(f.carchivo));
}

module.exports = { TIPOS, DOCUMENTOS, DECODIGO, documentos, resumenDe, subir, quitarTodos, requeridosPara };
