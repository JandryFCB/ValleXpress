const { Op } = require('sequelize');
const Direccion = require('./direccion.model');
const Usuario = require('../auth/usuario.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const CatalogoService = require('../../shared/services/catalogo.service');
const { TIPODIRECCIONLOCAL } = require('../../shared/constants/codigos');

// Lógica de negocio de las direcciones de entrega del cliente. Solo el dueño ve y modifica las suyas.
// Las direcciones son de la PERSONA (TPERSONADIRECCIONES.CPERSONA); el usuario que inicia sesión se traduce a su persona.
const MAXDIRECCIONES = 20;
// El local del negocio (LOC) lo maneja el módulo de vendedores: no es una dirección de entrega del cliente.
const DELCLIENTE = { tipo: { [Op.ne]: TIPODIRECCIONLOCAL } };
const num = (v) => (v === null || v === undefined ? null : Number(v));

const aApi = (d, usuarioId) => ({
  id: d.id,
  usuarioId,
  nombre: d.nombre,
  tipo: d.tipo,
  direccion: d.direccion,
  referencia: d.referencia,
  instrucciones: d.instrucciones,
  latitud: num(d.latitud),
  longitud: num(d.longitud),
  esPredeterminada: d.esPredeterminada,
  createdAt: d.creadoEn,
});

async function personaDe(usuarioId) {
  const u = await Usuario.findByPk(usuarioId, { attributes: ['id', 'personaId'] });
  if (!u) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return u.personaId;
}

async function propia(personaId, id) {
  const dir = await Direccion.findOne({ where: { id, personaId, ...DELCLIENTE } });
  if (!dir) throw AppError.notFound('Dirección no encontrada', 'DIRECCIONNOENCONTRADA');   // ajena o inexistente: mismo error
  return dir;
}

// Solo puede haber UNA predeterminada por usuario (la BD lo garantiza con un índice único)
const quitarPredeterminada = (personaId, usuarioId, excepto, t) => Direccion.update(
  { esPredeterminada: false, actualizadoPor: usuarioId },
  { where: { personaId, ...DELCLIENTE, esPredeterminada: true, ...(excepto && { id: { [Op.ne]: excepto } }) }, transaction: t },
);

const listar = async (usuarioId) => {
  const personaId = await personaDe(usuarioId);
  return (await Direccion.findAll({ where: { personaId, ...DELCLIENTE }, order: [['esPredeterminada', 'DESC'], ['creadoEn', 'DESC']] })).map((d) => aApi(d, usuarioId));
};

const predeterminada = async (usuarioId) => {
  const dir = await Direccion.findOne({ where: { personaId: await personaDe(usuarioId), ...DELCLIENTE, esPredeterminada: true } });
  return dir ? aApi(dir, usuarioId) : null;
};

async function crear(usuarioId, datos) {
  const personaId = await personaDe(usuarioId);
  if (await Direccion.count({ where: { personaId, ...DELCLIENTE } }) >= MAXDIRECCIONES) {
    throw AppError.conflict(`Puedes guardar hasta ${MAXDIRECCIONES} direcciones`, 'LIMITEDIRECCIONES');
  }
  const nueva = await withTransaction(async (t) => {
    if (datos.esPredeterminada === true) await quitarPredeterminada(personaId, usuarioId, null, t);
    return Direccion.create({
      personaId,
      tipo: datos.tipo || 'DOM',
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
  return aApi(nueva, usuarioId);
}

async function actualizar(usuarioId, id, datos) {
  const personaId = await personaDe(usuarioId);
  const dir = await propia(personaId, id);
  await withTransaction(async (t) => {
    if (datos.esPredeterminada === true) await quitarPredeterminada(personaId, usuarioId, dir.id, t);
    const cambios = { actualizadoPor: usuarioId };
    for (const campo of ['tipo', 'nombre', 'direccion', 'referencia', 'instrucciones', 'latitud', 'longitud']) {
      if (datos[campo] !== undefined) cambios[campo] = datos[campo];
    }
    if (datos.esPredeterminada !== undefined) cambios.esPredeterminada = datos.esPredeterminada === true;
    await dir.update(cambios, { transaction: t });
  }, { usuarioId });
  return aApi(dir, usuarioId);
}

async function marcarPredeterminada(usuarioId, id) {
  const personaId = await personaDe(usuarioId);
  const dir = await propia(personaId, id);
  await withTransaction(async (t) => {
    await quitarPredeterminada(personaId, usuarioId, dir.id, t);
    await dir.update({ esPredeterminada: true, actualizadoPor: usuarioId }, { transaction: t });
  }, { usuarioId });
  return aApi(dir, usuarioId);
}

async function eliminar(usuarioId, id) {
  const dir = await propia(await personaDe(usuarioId), id);
  await withTransaction((t) => dir.destroy({ transaction: t }), { usuarioId });       // borrado lógico (ELIMINADOEN)
}

const tipos = () => CatalogoService.tipos('ttiposdireccion', 'ctipodireccion', { excluir: [TIPODIRECCIONLOCAL] });

module.exports = { tipos, listar, predeterminada, crear, actualizar, marcarPredeterminada, eliminar };
