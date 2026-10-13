const { Op } = require('sequelize');
const Telefono = require('./telefono.model');
const Usuario = require('../auth/usuario.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const CatalogoService = require('../../shared/services/catalogo.service');

// Lógica de negocio de los teléfonos de la persona. Solo el dueño ve y modifica los suyos.
// Un teléfono no se puede repetir entre personas (lo garantiza la BD). El primero que se guarda queda como principal.
const MAXTELEFONOS = 5;

const aApi = (t) => ({
  id: t.id,
  numero: t.numero,
  tipo: t.tipo,
  principal: t.principal,
  verificado: t.verificado,
  createdAt: t.creadoEn,
});

async function personaDe(usuarioId) {
  const u = await Usuario.findByPk(usuarioId, { attributes: ['id', 'personaId'] });
  if (!u) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return u.personaId;
}

async function propio(personaId, id) {
  const tel = await Telefono.findOne({ where: { id, personaId } });
  if (!tel) throw AppError.notFound('Teléfono no encontrado', 'TELEFONONOENCONTRADO');     // ajeno o inexistente: mismo error
  return tel;
}

async function exigirLibre(numero, excepto) {
  const otro = await Telefono.findOne({ where: { numero, ...(excepto && { id: { [Op.ne]: excepto } }) }, attributes: ['id'] });
  if (otro) throw AppError.conflict('Este teléfono ya está registrado', 'TELEFONODUPLICADO');
}

const quitarPrincipal = (personaId, usuarioId, excepto, t) => Telefono.update(
  { principal: false, actualizadoPor: usuarioId },
  { where: { personaId, principal: true, ...(excepto && { id: { [Op.ne]: excepto } }) }, transaction: t },
);

const listar = async (usuarioId) => {
  const personaId = await personaDe(usuarioId);
  return (await Telefono.findAll({ where: { personaId }, order: [['principal', 'DESC'], ['creadoEn', 'ASC']] })).map(aApi);
};

const tipos = () => CatalogoService.tipos('ttipostelefono', 'ctipotelefono');

async function crear(usuarioId, datos) {
  const personaId = await personaDe(usuarioId);
  const cantidad = await Telefono.count({ where: { personaId } });
  if (cantidad >= MAXTELEFONOS) throw AppError.conflict(`Puedes guardar hasta ${MAXTELEFONOS} teléfonos`, 'LIMITETELEFONOS');
  await exigirLibre(datos.numero);
  const principal = cantidad === 0 || datos.principal === true || datos.principal === 'true';
  const nuevo = await withTransaction(async (t) => {
    if (principal) await quitarPrincipal(personaId, usuarioId, null, t);
    return Telefono.create({ personaId, numero: datos.numero, tipo: datos.tipo || 'MOV', principal, creadoPor: usuarioId }, { transaction: t });
  }, { usuarioId });
  return aApi(nuevo);
}

async function actualizar(usuarioId, id, datos) {
  const personaId = await personaDe(usuarioId);
  const tel = await propio(personaId, id);
  if (datos.numero && datos.numero !== tel.numero) await exigirLibre(datos.numero, tel.id);
  const quiereSerPrincipal = datos.principal === true || datos.principal === 'true';
  if ((datos.principal === false || datos.principal === 'false') && tel.principal) {
    throw AppError.badRequest('Marca otro teléfono como principal en lugar de quitar este', 'PRINCIPALREQUERIDO');
  }
  await withTransaction(async (t) => {
    if (quiereSerPrincipal) await quitarPrincipal(personaId, usuarioId, tel.id, t);
    const cambios = { actualizadoPor: usuarioId };
    if (datos.tipo) cambios.tipo = datos.tipo;
    if (quiereSerPrincipal) cambios.principal = true;
    // Otro número: hay que verificarlo de nuevo
    if (datos.numero && datos.numero !== tel.numero) Object.assign(cambios, { numero: datos.numero, verificado: false, verificadoEn: null });
    await tel.update(cambios, { transaction: t });
  }, { usuarioId });
  return aApi(tel);
}

const marcarPrincipal = (usuarioId, id) => actualizar(usuarioId, id, { principal: true });

// Si se borra el principal, el teléfono más antiguo que quede pasa a ser el principal.
async function eliminar(usuarioId, id) {
  const personaId = await personaDe(usuarioId);
  const tel = await propio(personaId, id);
  const eraPrincipal = tel.principal;
  await withTransaction(async (t) => {
    await tel.update({ principal: false, actualizadoPor: usuarioId }, { transaction: t });
    await tel.destroy({ transaction: t });                                       // borrado lógico (ELIMINADOEN)
    if (eraPrincipal) {
      const siguiente = await Telefono.findOne({ where: { personaId }, order: [['creadoEn', 'ASC']], transaction: t });
      if (siguiente) await siguiente.update({ principal: true, actualizadoPor: usuarioId }, { transaction: t });
    }
  }, { usuarioId });
}

module.exports = { listar, tipos, crear, actualizar, marcarPrincipal, eliminar };
