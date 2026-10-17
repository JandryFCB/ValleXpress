const { Op, Sequelize } = require('sequelize');
const Direccion = require('./direccion.model');
const Usuario = require('../auth/usuario.model');
const ZonaService = require('../../shared/services/zona.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const CatalogoService = require('../../shared/services/catalogo.service');
const { TIPODIRECCION, TIPODIRECCIONAAPI, TIPODIRECCIONLOCAL } = require('../../shared/constants/codigos');

// Lógica de negocio de las direcciones de entrega del cliente. Solo el dueño ve y modifica las suyas.
// Las direcciones son de la PERSONA (TPERSONADIRECCIONES.CPERSONA); el usuario que inicia sesión se traduce a su persona.
// Cada cambio queda en el historial de la misma tabla (FDESDE/FHASTA) y registra quién lo hizo.
const MAXDIRECCIONES = 20;
// El local del negocio (tipo 005) lo maneja el módulo de negocios: no es una dirección de entrega del cliente.
const DELCLIENTE = { tipo: { [Op.ne]: TIPODIRECCIONLOCAL } };
const num = (v) => (v === null || v === undefined ? null : Number(v));

// La fecha de creación es el FDESDE de la PRIMERA versión (el FDESDE de la fila vigente es el del último cambio)
const CREADOEN = [Sequelize.literal('(SELECT MIN(h.fdesde) FROM tpersonadirecciones h WHERE h.cdireccion = "Direccion"."cdireccion")'), 'creadoEn'];
const CONCREACION = { include: [CREADOEN] };

const aApi = (d, usuarioId) => ({
  id: Number(d.id),
  usuarioId,
  nombre: d.nombre,
  tipo: TIPODIRECCIONAAPI[d.tipo],
  direccion: d.direccion,
  referencia: d.referencia,
  instrucciones: d.instrucciones,
  latitud: num(d.latitud),
  longitud: num(d.longitud),
  esPredeterminada: d.esPredeterminada,
  createdAt: d.get('creadoEn') ?? d.fDesde,
  updatedAt: d.fDesde,
});

async function personaDe(usuarioId) {
  const u = await Usuario.findByPk(usuarioId, { attributes: ['id', 'personaId'] });
  if (!u) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return u.personaId;
}

async function propia(personaId, id, opciones = {}) {
  const dir = await Direccion.findOne({ where: { id, personaId, ...DELCLIENTE }, attributes: CONCREACION, ...opciones });
  if (!dir) throw AppError.notFound('Dirección no encontrada', 'DIRECCIONNOENCONTRADA');   // ajena o inexistente: mismo error
  return dir;
}

// Solo puede haber UNA predeterminada por persona (la BD lo garantiza con un índice único entre las vigentes)
const quitarPredeterminada = (personaId, excepto, t) => Direccion.update(
  { esPredeterminada: false },
  { where: { personaId, ...DELCLIENTE, esPredeterminada: true, ...(excepto && { id: { [Op.ne]: excepto } }) }, transaction: t },
);

const listar = async (usuarioId) => {
  const personaId = await personaDe(usuarioId);
  const filas = await Direccion.findAll({
    where: { personaId, ...DELCLIENTE },
    attributes: CONCREACION,
    order: [['esPredeterminada', 'DESC'], ['id', 'DESC']],
  });
  return filas.map((d) => aApi(d, usuarioId));
};

const predeterminada = async (usuarioId) => {
  const dir = await Direccion.findOne({
    where: { personaId: await personaDe(usuarioId), ...DELCLIENTE, esPredeterminada: true },
    attributes: CONCREACION,
  });
  return dir ? aApi(dir, usuarioId) : null;
};

async function crear(usuarioId, datos) {
  const personaId = await personaDe(usuarioId);
  if (await Direccion.count({ where: { personaId, ...DELCLIENTE } }) >= MAXDIRECCIONES) {
    throw AppError.conflict(`Puedes guardar hasta ${MAXDIRECCIONES} direcciones`, 'LIMITEDIRECCIONES');
  }
  await ZonaService.exigirDentro({ lat: Number(datos.latitud), lng: Number(datos.longitud) });
  const nueva = await withTransaction(async (t) => {
    if (datos.esPredeterminada === true) await quitarPredeterminada(personaId, null, t);
    return Direccion.create({
      personaId,
      tipo: TIPODIRECCION[datos.tipo] || TIPODIRECCION.DOM,
      nombre: datos.nombre || null,
      direccion: datos.direccion.trim(),
      referencia: datos.referencia?.trim() || null,
      instrucciones: datos.instrucciones?.trim() || null,
      latitud: datos.latitud,
      longitud: datos.longitud,
      esPredeterminada: datos.esPredeterminada === true,
    }, { transaction: t });
  }, { usuarioId });
  return aApi(nueva, usuarioId);
}

async function actualizar(usuarioId, id, datos) {
  const personaId = await personaDe(usuarioId);
  const dir = await propia(personaId, id);
  if (datos.latitud !== undefined || datos.longitud !== undefined) {
    await ZonaService.exigirDentro({ lat: Number(datos.latitud ?? dir.latitud), lng: Number(datos.longitud ?? dir.longitud) });
  }
  await withTransaction(async (t) => {
    if (datos.esPredeterminada === true) await quitarPredeterminada(personaId, dir.id, t);
    const cambios = {};
    for (const campo of ['nombre', 'direccion', 'referencia', 'instrucciones', 'latitud', 'longitud']) {
      if (datos[campo] === undefined) continue;
      // La app manda texto vacío para BORRAR un dato opcional: en la BD queda vacío de verdad (null), no ''
      const borrar = ['nombre', 'referencia', 'instrucciones'].includes(campo) && typeof datos[campo] === 'string' && datos[campo].trim() === '';
      cambios[campo] = borrar ? null : datos[campo];
    }
    if (datos.tipo !== undefined) cambios.tipo = TIPODIRECCION[datos.tipo];
    if (datos.esPredeterminada !== undefined) cambios.esPredeterminada = datos.esPredeterminada === true;
    await dir.update(cambios, { transaction: t });
  }, { usuarioId });
  return aApi(dir, usuarioId);
}

async function marcarPredeterminada(usuarioId, id) {
  const personaId = await personaDe(usuarioId);
  const dir = await propia(personaId, id);
  await withTransaction(async (t) => {
    await quitarPredeterminada(personaId, dir.id, t);
    await dir.update({ esPredeterminada: true }, { transaction: t });
  }, { usuarioId });
  return aApi(dir, usuarioId);
}

// Se borra la fila vigente; el trigger deja una copia cerrada en el historial (nada se pierde)
async function eliminar(usuarioId, id) {
  const dir = await propia(await personaDe(usuarioId), id);
  await withTransaction((t) => dir.destroy({ transaction: t }), { usuarioId });
}

const tipos = () => CatalogoService.tipos('ttiposdireccion', 'ctipodireccion', TIPODIRECCIONAAPI, { excluir: [TIPODIRECCIONLOCAL] });

module.exports = { tipos, listar, predeterminada, crear, actualizar, marcarPredeterminada, eliminar };
