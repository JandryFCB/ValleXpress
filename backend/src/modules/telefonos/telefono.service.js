const { Op, Sequelize } = require('sequelize');
const Telefono = require('./telefono.model');
const Usuario = require('../auth/usuario.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const CatalogoService = require('../../shared/services/catalogo.service');
const { TIPOTELEFONO, TIPOTELEFONOAAPI } = require('../../shared/constants/codigos');

// Lógica de negocio de los teléfonos de la persona. Solo el dueño ve y modifica los suyos.
// Un teléfono no se puede repetir entre personas (lo garantiza la BD). El primero que se guarda queda como principal.
// El "id" que ve la app es la secuencia del teléfono dentro de la persona (1, 2, 3...). Cada cambio queda en el
// historial de la misma tabla (FDESDE/FHASTA) y registra quién lo hizo.
const MAXTELEFONOS = 5;

// La fecha de creación es el FDESDE de la PRIMERA versión
const CREADOEN = [Sequelize.literal('(SELECT MIN(h.fdesde) FROM tpersonatelefonos h WHERE h.cpersona = "Telefono"."cpersona" AND h.stelefono = "Telefono"."stelefono")'), 'creadoEn'];
const CONCREACION = { include: [CREADOEN] };

const aApi = (t) => ({
  id: t.secuencia,
  numero: t.numero,
  tipo: TIPOTELEFONOAAPI[t.tipo],
  principal: t.principal,
  verificado: !!t.verificadoEn,
  createdAt: t.get('creadoEn') ?? t.fDesde,
  updatedAt: t.fDesde,
});

async function personaDe(usuarioId) {
  const u = await Usuario.findByPk(usuarioId, { attributes: ['id', 'personaId'] });
  if (!u) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return u.personaId;
}

async function propio(personaId, id) {
  const tel = await Telefono.findOne({ where: { personaId, secuencia: id }, attributes: CONCREACION });
  if (!tel) throw AppError.notFound('Teléfono no encontrado', 'TELEFONONOENCONTRADO');     // ajeno o inexistente: mismo error
  return tel;
}

async function exigirLibre(numero, personaId, excepto) {
  const otro = await Telefono.findOne({ where: { numero }, attributes: ['personaId', 'secuencia'] });
  if (otro && !(String(otro.personaId) === String(personaId) && otro.secuencia === excepto)) {
    throw AppError.conflict('Este teléfono ya está registrado', 'TELEFONODUPLICADO');
  }
}

const quitarPrincipal = (personaId, excepto, t) => Telefono.update(
  { principal: false },
  { where: { personaId, principal: true, ...(excepto && { secuencia: { [Op.ne]: excepto } }) }, transaction: t },
);

const listar = async (usuarioId) => {
  const personaId = await personaDe(usuarioId);
  const filas = await Telefono.findAll({ where: { personaId }, attributes: CONCREACION, order: [['principal', 'DESC'], ['secuencia', 'ASC']] });
  return filas.map(aApi);
};

const tipos = () => CatalogoService.tipos('ttipostelefono', 'ctipotelefono', TIPOTELEFONOAAPI);

async function crear(usuarioId, datos) {
  const personaId = await personaDe(usuarioId);
  const cantidad = await Telefono.count({ where: { personaId } });
  if (cantidad >= MAXTELEFONOS) throw AppError.conflict(`Puedes guardar hasta ${MAXTELEFONOS} teléfonos`, 'LIMITETELEFONOS');
  await exigirLibre(datos.numero, personaId, null);
  const principal = cantidad === 0 || datos.principal === true || datos.principal === 'true';
  const nuevo = await withTransaction(async (t) => {
    if (principal) await quitarPrincipal(personaId, null, t);
    return Telefono.create({ personaId, numero: datos.numero, tipo: TIPOTELEFONO[datos.tipo] || TIPOTELEFONO.MOV, principal }, { transaction: t });
  }, { usuarioId });
  return aApi(nuevo);
}

async function actualizar(usuarioId, id, datos) {
  const personaId = await personaDe(usuarioId);
  const tel = await propio(personaId, id);
  if (datos.numero && datos.numero !== tel.numero) await exigirLibre(datos.numero, personaId, tel.secuencia);
  const quiereSerPrincipal = datos.principal === true || datos.principal === 'true';
  if ((datos.principal === false || datos.principal === 'false') && tel.principal) {
    throw AppError.badRequest('Marca otro teléfono como principal en lugar de quitar este', 'PRINCIPALREQUERIDO');
  }
  await withTransaction(async (t) => {
    if (quiereSerPrincipal) await quitarPrincipal(personaId, tel.secuencia, t);
    const cambios = {};
    if (datos.tipo) cambios.tipo = TIPOTELEFONO[datos.tipo];
    if (quiereSerPrincipal) cambios.principal = true;
    // Otro número: hay que verificarlo de nuevo
    if (datos.numero && datos.numero !== tel.numero) Object.assign(cambios, { numero: datos.numero, verificadoEn: null });
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
    await tel.destroy({ transaction: t });                      // el trigger deja la copia cerrada en el historial
    if (eraPrincipal) {
      const siguiente = await Telefono.findOne({ where: { personaId }, order: [['secuencia', 'ASC']], transaction: t });
      if (siguiente) await siguiente.update({ principal: true }, { transaction: t });
    }
  }, { usuarioId });
}

module.exports = { listar, tipos, crear, actualizar, marcarPrincipal, eliminar };
