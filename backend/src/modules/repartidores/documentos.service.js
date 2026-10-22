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
  const faltan = lista.filter((d) => !d.subido).length;
  // Hasta cuándo tiene para subirlos (solo si está pendiente y le faltan)
  const plazo = faltan && estado?.aprobacion === APROBACION.PENDIENTE ? await plazoDe(usuarioId) : null;
  return { documentos: lista, completos: !faltan, faltan, aprobacion: APROBACIONAAPI[estado?.aprobacion] || 'pendiente', ...(plazo && { plazoHasta: plazo.hasta }) };
}

// Cuántos documentos subió cada repartidor y cuántos le piden (para la lista de aprobaciones del admin)
async function resumenDe(repartidores) {
  if (!repartidores.length) return {};
  const filas = await consulta('SELECT cusuario, tipo FROM trepartidordocumentos WHERE cusuario IN (:u)', { u: repartidores.map((r) => r.usuarioId) });
  return Object.fromEntries(repartidores.map((r) => {
    const requeridos = requeridosPara(r.vehiculo);
    const tiene = (d) => filas.some((f) => f.cusuario === r.usuarioId && f.tipo === d.codigo);
    const subidos = requeridos.filter(tiene).length;
    // "faltan": los nombres de los que no ha subido (el admin los ve antes de aprobarlo igual)
    return [r.usuarioId, { subidos, requeridos: requeridos.length, faltan: requeridos.filter((d) => !tiene(d)).map((d) => d.titulo) }];
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

// ---------------------------------------------------------------------------------------------
// Plazo para subir los documentos (DOCUMENTOSPLAZODIAS, 7 por defecto). Cuenta desde que la solicitud quedó
// pendiente (al registrarse o al pedir revisión). Mientras le falten documentos:
//   día 1 → recordatorio · día 3 → "te quedan N días" · al vencer → la solicitud se cierra (rechazada, con el
//   motivo); su cuenta sigue y puede pedir revisión cuando los suba.
// Si ya subió todos, no se cierra nada (falta la revisión del administrador). Avisos solo de 8:00 a 21:00.
// ---------------------------------------------------------------------------------------------
const ConfiguracionService = require('../../shared/services/configuracion.service');
const plazoDias = async () => Math.max(1, Number(await ConfiguracionService.obtener('DOCUMENTOSPLAZODIAS', 7)) || 7);
const TIPOAVISO = 'documentos_recordatorio';

// Repartidores pendientes, desde cuándo y cuántos documentos les faltan
async function pendientesDeDocumentos(usuarios) {
  const filtro = usuarios ? 'AND r.cusuario IN (:usuarios)' : '';
  const filas = await consulta(`
    WITH h AS (
      SELECT cusuario, cestatusaprobacion, fdesde, LAG(cestatusaprobacion) OVER (PARTITION BY cusuario ORDER BY fdesde) AS anterior
        FROM trepartidores)
    SELECT r.cusuario, r.ctipovehiculo AS vehiculo,
           (SELECT MAX(h.fdesde) FROM h WHERE h.cusuario = r.cusuario AND h.cestatusaprobacion = '001' AND (h.anterior IS NULL OR h.anterior <> '001')) AS desde
      FROM trepartidores r
      JOIN tusuarios u ON u.cusuario = r.cusuario AND u.fhasta = '2999-12-31 00:00:00-05' AND u.cestatususuario = '001'
     WHERE r.fhasta = '2999-12-31 00:00:00-05' AND r.cestatusaprobacion = '001' ${filtro}`,
  usuarios ? { usuarios } : {});
  if (!filas.length) return [];
  const docs = await consulta('SELECT cusuario, tipo FROM trepartidordocumentos WHERE cusuario IN (:u)', { u: filas.map((f) => f.cusuario) });
  return filas.map((f) => {
    const requeridos = requeridosPara(f.vehiculo).map((d) => d.codigo);
    const faltan = requeridos.filter((c) => !docs.some((d) => d.cusuario === f.cusuario && d.tipo === c)).length;
    return { usuario: f.cusuario, desde: new Date(f.desde), faltan };
  });
}

// Hasta cuándo tiene para subirlos (null si no está pendiente o ya los subió todos)
async function plazoDe(usuarioId) {
  const [p] = await pendientesDeDocumentos([usuarioId]);
  if (!p || !p.faltan) return null;
  const dias = await plazoDias();
  return { hasta: new Date(p.desde.getTime() + dias * 86400000), dias };
}

async function vigilarDocumentos({ io, ahora = new Date() } = {}) {
  const hora = new Date(ahora.getTime() - 5 * 3600 * 1000).getUTCHours();
  if (hora < 8 || hora >= 21) return 0;
  const plazo = await plazoDias();
  const Correo = require('../../shared/services/correo.service');
  let hechos = 0;
  for (const p of (await pendientesDeDocumentos()).filter((x) => x.faltan > 0)) {
    const dias = (ahora - p.desde) / 86400000;
    const etapa = dias >= plazo ? 'cierre' : dias >= 3 ? 'segundo' : dias >= 1 ? 'primero' : null;
    if (!etapa) continue;
    const clave = `${p.desde.toISOString()}:${etapa}`;
    const [ya] = await consulta("SELECT 1 FROM tnotificaciones WHERE cusuario = :u AND tipo = :tipo AND datos->>'clave' = :clave LIMIT 1", { u: p.usuario, tipo: TIPOAVISO, clave });
    if (ya) continue;
    const quedan = Math.max(1, Math.ceil(plazo - dias));
    const docs = p.faltan === 1 ? '1 documento' : `${p.faltan} documentos`;
    if (etapa === 'cierre') {
      const motivo = `No subiste tus documentos en ${plazo} días. Súbelos y pide una nueva revisión`;
      await sequelize.query(
        "UPDATE trepartidores SET cestatusaprobacion = '003', motivoaprobacion = :motivo WHERE cusuario = :u AND fhasta = '2999-12-31 00:00:00-05' AND cestatusaprobacion = '001'",
        { replacements: { u: p.usuario, motivo } },
      );
      auditar({ accion: 'SOLICITUDCERRADAPORDOCUMENTOS', entidad: 'REPARTIDORES', entidadId: p.usuario, detalle: { faltan: p.faltan, plazo } });
      await NotificacionService.notificar({ io, usuarioId: p.usuario, tipo: TIPOAVISO, titulo: 'Cerramos tu solicitud de repartidor', mensaje: `${motivo}.`, datos: { clave } });
      const [u] = await consulta('SELECT email, nombres FROM vusuarios WHERE usuario = :u', { u: p.usuario });
      if (u?.email) {
        Correo.avisoCuenta({
          para: u.email, nombre: u.nombres, asunto: 'Tu solicitud de repartidor se cerró', titulo: 'Te faltaron documentos',
          parrafos: [`Pasaron ${plazo} días y aún te faltan ${docs}, así que cerramos tu solicitud.`, 'Cuando quieras, súbelos en la app (Perfil → Mis documentos) y toca "Pedir revisión".'],
        });
      }
    } else {
      await NotificacionService.notificar({
        io, usuarioId: p.usuario, tipo: TIPOAVISO,
        titulo: etapa === 'primero' ? 'Sube tus documentos para empezar 📄' : `Te quedan ${quedan} ${quedan === 1 ? 'día' : 'días'} para subir tus documentos`,
        mensaje: `Te faltan ${docs}. Súbelos en Perfil → Mis documentos para que podamos aprobarte${etapa === 'segundo' ? '; si no, cerraremos tu solicitud' : ''}.`,
        datos: { clave },
      });
    }
    hechos += 1;
  }
  return hechos;
}

// Revisa cada 30 minutos (y una vez al arrancar). No impide que el proceso termine.
function iniciarVigilancia(io) {
  const pasada = () => vigilarDocumentos({ io }).catch(() => {});
  setTimeout(pasada, 15 * 1000).unref();
  return setInterval(pasada, 30 * 60 * 1000).unref();
}

module.exports = { TIPOS, DOCUMENTOS, DECODIGO, documentos, resumenDe, subir, quitarTodos, requeridosPara, plazoDe, plazoDias, vigilarDocumentos, iniciarVigilancia };
