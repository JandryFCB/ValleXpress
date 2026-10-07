const { Op } = require('sequelize');
const Direccion = require('./direccion.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');

// Lógica de negocio de las direcciones de entrega del cliente. Solo el dueño ve y modifica las suyas.
const MAXDIRECCIONES = 20;
const num = (v) => (v === null || v === undefined ? null : Number(v));

const aApi = (d) => ({
  id: d.id,
  usuarioId: d.usuarioId,
  nombre: d.nombre,
  direccion: d.direccion,
  referencia: d.referencia,
  instrucciones: d.instrucciones,
  latitud: num(d.latitud),
  longitud: num(d.longitud),
  esPredeterminada: d.esPredeterminada,
  createdAt: d.creadoEn,
});

async function propia(usuarioId, id) {
  const dir = await Direccion.findOne({ where: { id, usuarioId } });
  if (!dir) throw AppError.notFound('Dirección no encontrada', 'DIRECCIONNOENCONTRADA');   // ajena o inexistente: mismo error
  return dir;
}

// Solo puede haber UNA predeterminada por usuario (la BD lo garantiza con un índice único)
const quitarPredeterminada = (usuarioId, excepto, t) => Direccion.update(
  { esPredeterminada: false, actualizadoPor: usuarioId },
  { where: { usuarioId, esPredeterminada: true, ...(excepto && { id: { [Op.ne]: excepto } }) }, transaction: t },
);

const listar = async (usuarioId) =>
  (await Direccion.findAll({ where: { usuarioId }, order: [['esPredeterminada', 'DESC'], ['creadoEn', 'DESC']] })).map(aApi);

const predeterminada = async (usuarioId) => {
  const dir = await Direccion.findOne({ where: { usuarioId, esPredeterminada: true } });
  return dir ? aApi(dir) : null;
};

async function crear(usuarioId, datos) {
  if (await Direccion.count({ where: { usuarioId } }) >= MAXDIRECCIONES) {
    throw AppError.conflict(`Puedes guardar hasta ${MAXDIRECCIONES} direcciones`, 'LIMITEDIRECCIONES');
  }
  const nueva = await withTransaction(async (t) => {
    if (datos.esPredeterminada === true) await quitarPredeterminada(usuarioId, null, t);
    return Direccion.create({
      usuarioId,
      nombre: datos.nombre || null,
      direccion: datos.direccion.trim(),
      referencia: datos.referencia,
      instrucciones: datos.instrucciones,
      latitud: datos.latitud,
      longitud: datos.longitud,
      esPredeterminada: datos.esPredeterminada === true,
      creadoPor: usuarioId,
    }, { transaction: t });
  }, { usuarioId });
  return aApi(nueva);
}

async function actualizar(usuarioId, id, datos) {
  const dir = await propia(usuarioId, id);
  await withTransaction(async (t) => {
    if (datos.esPredeterminada === true) await quitarPredeterminada(usuarioId, dir.id, t);
    const cambios = { actualizadoPor: usuarioId };
    for (const campo of ['nombre', 'direccion', 'referencia', 'instrucciones', 'latitud', 'longitud']) {
      if (datos[campo] !== undefined) cambios[campo] = datos[campo];
    }
    if (datos.esPredeterminada !== undefined) cambios.esPredeterminada = datos.esPredeterminada === true;
    await dir.update(cambios, { transaction: t });
  }, { usuarioId });
  return aApi(dir);
}

async function marcarPredeterminada(usuarioId, id) {
  const dir = await propia(usuarioId, id);
  await withTransaction(async (t) => {
    await quitarPredeterminada(usuarioId, dir.id, t);
    await dir.update({ esPredeterminada: true, actualizadoPor: usuarioId }, { transaction: t });
  }, { usuarioId });
  return aApi(dir);
}

async function eliminar(usuarioId, id) {
  const dir = await propia(usuarioId, id);
  await withTransaction((t) => dir.destroy({ transaction: t }), { usuarioId });       // borrado lógico (ELIMINADOEN)
}

module.exports = { listar, predeterminada, crear, actualizar, marcarPredeterminada, eliminar };
