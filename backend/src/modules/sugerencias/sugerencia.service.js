const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const NotificacionService = require('../notificaciones/notificacion.service');
const { auditar } = require('../../shared/services/log.service');
const { ROLAAPI } = require('../../shared/constants/codigos');

// SUGERENCIAS ("Ayúdanos a mejorar ValleXpress"): clientes, vendedores y repartidores mandan ideas, problemas o
// felicitaciones; los administradores las ven, las marcan como leídas o atendidas y pueden responder (a la persona
// le llega el aviso). Máximo 5 por persona al día, para que no se convierta en spam.
const VIGENTE = "'2999-12-31 00:00:00-05'";
const TIPOS = ['sugerencia', 'problema', 'felicitacion'];
const ESTADOS = ['nueva', 'leida', 'atendida'];
const MAXPORDIA = 5;
const NOMBRETIPO = { sugerencia: 'Sugerencia', problema: 'Problema', felicitacion: 'Felicitación' };

const consulta = (sql, replacements = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT });

const aApi = (f, { admin = false } = {}) => ({
  id: Number(f.csugerencia),
  tipo: f.tipo.toLowerCase(),
  mensaje: f.mensaje,
  satisfaccion: f.satisfaccion,
  estado: f.estado.toLowerCase(),
  respuesta: f.respuesta,
  fecha: f.fcreacion,
  respondidaEn: f.frevision,
  ...(admin && {
    usuario: f.cusuario,
    rol: ROLAAPI[f.crol],
    nombre: [f.nombres, f.apellidos].filter(Boolean).join(' ') || f.cusuario,
    versionApp: f.versionapp,
    revisadaPor: f.cusuario_revision,
  }),
});

async function crear(usuario, { tipo = 'sugerencia', mensaje, satisfaccion, versionApp }, req) {
  const [{ n }] = await consulta(
    "SELECT COUNT(*)::int AS n FROM tsugerencias WHERE cusuario = :u AND fcreacion > now() - interval '1 day'", { u: usuario.id },
  );
  if (n >= MAXPORDIA) throw AppError.tooMany('Ya nos enviaste varias hoy. ¡Gracias! Vuelve a escribirnos mañana', 'DEMASIADASSUGERENCIAS');
  const [fila] = await sequelize.query(
    `INSERT INTO tsugerencias (cusuario, crol, tipo, mensaje, satisfaccion, versionapp)
     VALUES (:u, :rol, :tipo, :mensaje, :satisfaccion, :version) RETURNING *`,
    { replacements: { u: usuario.id, rol: usuario.rol, tipo: tipo.toUpperCase(), mensaje: mensaje.trim(), satisfaccion: satisfaccion ?? null, version: versionApp || null }, type: QueryTypes.SELECT },
  );
  auditar({ usuarioId: usuario.id, accion: 'SUGERENCIAENVIADA', entidad: 'SUGERENCIAS', entidadId: fila.csugerencia, detalle: { tipo }, req });
  const corto = mensaje.trim().length > 90 ? `${mensaje.trim().slice(0, 90)}…` : mensaje.trim();
  await NotificacionService.notificarAdministradores({
    io: req.io, tipo: 'sugerencia_nueva', titulo: `${NOMBRETIPO[tipo]} de ${usuario.nombre || usuario.id} 💡`,
    mensaje: `(${usuario.tipoUsuario}) ${corto}`,
  });
  return aApi(fila);
}

const mias = async (usuarioId) => (await consulta('SELECT * FROM tsugerencias WHERE cusuario = :u ORDER BY fcreacion DESC LIMIT 30', { u: usuarioId })).map((f) => aApi(f));

// Administrador: las sugerencias (las nuevas primero), con cuántas hay en cada estado
async function listar({ estado, tipo } = {}) {
  const filtros = [];
  if (ESTADOS.includes(estado)) filtros.push(`s.estado = '${estado.toUpperCase()}'`);
  if (TIPOS.includes(tipo)) filtros.push(`s.tipo = '${tipo.toUpperCase()}'`);
  const filas = await consulta(`
    SELECT s.*, p.nombres, p.apellidos
      FROM tsugerencias s
      LEFT JOIN tusuarios u ON u.cusuario = s.cusuario AND u.fhasta = ${VIGENTE}
      LEFT JOIN tpersonas p ON p.cpersona = u.cpersona AND p.fhasta = ${VIGENTE}
     ${filtros.length ? `WHERE ${filtros.join(' AND ')}` : ''}
     ORDER BY (s.estado = 'NUEVA') DESC, s.fcreacion DESC LIMIT 200`);
  const conteos = Object.fromEntries((await consulta('SELECT lower(estado) AS e, COUNT(*)::int AS n FROM tsugerencias GROUP BY estado')).map((f) => [f.e, f.n]));
  const [{ promedio }] = await consulta('SELECT ROUND(AVG(satisfaccion), 1) AS promedio FROM tsugerencias WHERE satisfaccion IS NOT NULL');
  return { sugerencias: filas.map((f) => aApi(f, { admin: true })), conteos, satisfaccionPromedio: promedio == null ? null : Number(promedio) };
}

const nuevas = async () => (await consulta("SELECT COUNT(*)::int AS n FROM tsugerencias WHERE estado = 'NUEVA'"))[0].n;

// Marcar como leída o atendida y, si hay respuesta, avisarle a la persona
async function atender(admin, id, { estado, respuesta }, req) {
  const [actual] = await consulta('SELECT * FROM tsugerencias WHERE csugerencia = :id', { id });
  if (!actual) throw AppError.notFound('Sugerencia no encontrada', 'SUGERENCIANOENCONTRADA');
  const texto = respuesta?.trim() || null;
  const nuevoEstado = (estado || (texto ? 'atendida' : 'leida')).toUpperCase();
  const [fila] = await sequelize.query(
    `UPDATE tsugerencias SET estado = :estado, respuesta = COALESCE(:respuesta, respuesta), frevision = now(), cusuario_revision = :admin
      WHERE csugerencia = :id RETURNING *`,
    { replacements: { id, estado: nuevoEstado, respuesta: texto, admin: admin.id }, type: QueryTypes.SELECT },
  );
  auditar({ usuarioId: admin.id, accion: 'SUGERENCIAATENDIDA', entidad: 'SUGERENCIAS', entidadId: id, detalle: { estado: nuevoEstado, respondio: !!texto }, req });
  if (texto) {
    await NotificacionService.notificar({
      io: req.io, usuarioId: actual.cusuario, tipo: 'sugerencia_respondida', titulo: 'ValleXpress respondió tu mensaje 💬',
      mensaje: texto.length > 140 ? `${texto.slice(0, 140)}…` : texto,
    });
  }
  return aApi(fila, { admin: true });
}

module.exports = { TIPOS, ESTADOS, crear, mias, listar, nuevas, atender };
