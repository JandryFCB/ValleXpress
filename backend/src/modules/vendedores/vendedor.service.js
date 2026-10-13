const Vendedor = require('./vendedor.model');
const HorarioVendedor = require('./horarioVendedor.model');
const Usuario = require('../auth/usuario.model');
const Direccion = require('../direcciones/direccion.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const CatalogoService = require('../../shared/services/catalogo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { auditar } = require('../../shared/services/log.service');
const { APROBACION } = require('../../shared/constants/codigos');

// Lógica de negocio de los vendedores. El controller solo llama a estos métodos.

const INCLUIR = [
  { model: Usuario, as: 'usuario', attributes: ['id', 'personaId', 'nombre', 'apellido', 'email', 'telefono'] },
  { model: Direccion, as: 'local', required: false },
  { model: HorarioVendedor, as: 'horarios', required: false },
];
const VISIBLE = { aprobacion: APROBACION.APROBADO, activo: true };      // lo que ve el público
const num = (v) => (v === null || v === undefined ? null : Number(v));
const hhmm = (t) => (t ? String(t).slice(0, 5) : null);
const LUNES = 1;

// Convierte vendedores al formato que consume la app. privado=true agrega el correo y el teléfono del dueño
// (solo para el propio vendedor); en las consultas públicas NO se exponen datos personales.
async function aApi(entrada, req, { privado = false } = {}) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  const urls = await ArchivoService.mapaUrls(req, lista.flatMap((v) => [v.logoId, v.bannerId]));
  const salida = await Promise.all(lista.map(async (v) => {
    const horario = (v.horarios || []).find((h) => h.dia === LUNES) || (v.horarios || [])[0];
    const u = v.usuario;
    return {
      id: v.id,
      usuarioId: v.usuarioId,
      nombreNegocio: v.nombreNegocio,
      descripcion: v.descripcion,
      logo: urls[v.logoId]?.url || null,
      logoMiniatura: urls[v.logoId]?.miniatura || null,
      banner: urls[v.bannerId]?.url || null,
      categoria: await CatalogoService.categoriaTexto(v),
      categoriaCodigo: v.categoria,
      calificacionPromedio: num(v.calificacionPromedio),
      totalCalificaciones: v.totalCalificaciones,
      horarioApertura: hhmm(horario?.apertura),
      horarioCierre: hhmm(horario?.cierre),
      diasAtencion: null,
      tiempoPreparacionPromedio: v.tiempoPreparacionPromedio,
      costoDelivery: num(v.costoDelivery),
      radioCobertura: num(v.radioCobertura),
      abiertoAhora: v.abiertoAhora,
      latitud: num(v.local?.latitud),
      longitud: num(v.local?.longitud),
      aprobacion: v.aprobacion,
      createdAt: v.creadoEn,
      ...(u && { usuario: privado ? { id: u.id, nombre: u.nombre, apellido: u.apellido, email: u.email, telefono: u.telefono } : { id: u.id, nombre: u.nombre, apellido: u.apellido } }),
    };
  }));
  return Array.isArray(entrada) ? salida : salida[0];
}

async function delUsuario(usuarioId, mensaje = 'Vendedor no encontrado', opciones = {}) {
  const vendedor = await Vendedor.findOne({ where: { id: usuarioId }, include: INCLUIR, ...opciones });
  if (!vendedor) throw AppError.notFound(mensaje, 'VENDEDORNOENCONTRADO');
  return vendedor;
}

// Crea el perfil de vendedor (lo usa el registro y POST /vendedores).
async function crearPerfil(usuarioId, datos, { transaction, nombreUsuario = '' } = {}) {
  const { categoria, datosExtra } = CatalogoService.categoriaParaGuardar(datos.categoria ?? datos.categoriaNegocio);
  const estado = await ConfiguracionService.aprobacionInicial();
  return Vendedor.create({
    id: usuarioId,
    nombreNegocio: (datos.nombreNegocio || '').trim() || `Negocio de ${nombreUsuario}`,
    descripcion: (datos.descripcion ?? datos.descripcionNegocio ?? '').trim() || 'Cuéntanos sobre tu negocio',
    categoria,
    datosExtra,
    costoDelivery: datos.costoDelivery,
    radioCobertura: datos.radioCobertura,
    aprobacion: estado.aprobacion,
    aprobadoEn: estado.aprobadoEn,
    creadoPor: usuarioId,
  }, { transaction });
}

async function listar(req) {
  const vendedores = await Vendedor.findAll({ where: VISIBLE, include: INCLUIR, order: [['creadoEn', 'DESC']] });
  return { vendedores: await aApi(vendedores, req) };
}

async function obtener(id, req) {
  const vendedor = await Vendedor.findOne({ where: { id, ...VISIBLE }, include: INCLUIR });
  if (!vendedor) throw AppError.notFound('Vendedor no encontrado', 'VENDEDORNOENCONTRADO');
  return { vendedor: await aApi(vendedor, req) };
}

async function miPerfil(usuarioId, req) {
  const vendedor = await delUsuario(usuarioId, 'No tienes un perfil de vendedor registrado');
  return { vendedor: await aApi(vendedor, req, { privado: true }) };
}

async function crear(usuarioId, datos, req) {
  if (await Vendedor.findOne({ where: { id: usuarioId } })) throw AppError.conflict('Ya tienes un negocio registrado', 'NEGOCIOEXISTENTE');
  const nuevo = await withTransaction((t) => crearPerfil(usuarioId, datos, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'NEGOCIOCREADO', entidad: 'TNEGOCIOS', entidadId: nuevo.id, req });
  return { vendedor: await aApi(await delUsuario(usuarioId), req, { privado: true }) };
}

// Mismo horario para los 7 días (la app maneja una sola hora de apertura y una de cierre)
async function fijarHorario(vendedorId, apertura, cierre, usuarioId, transaction) {
  for (let dia = 1; dia <= 7; dia += 1) {
    const fila = await HorarioVendedor.findOne({ where: { vendedorId, dia }, transaction });
    if (fila) await fila.update({ apertura: apertura ?? fila.apertura, cierre: cierre ?? fila.cierre, cerrado: false, actualizadoPor: usuarioId }, { transaction });
    else await HorarioVendedor.create({ vendedorId, dia, apertura, cierre, creadoPor: usuarioId }, { transaction });
  }
}

async function actualizar(usuarioId, datos, req) {
  await withTransaction(async (t) => {
    const vendedor = await delUsuario(usuarioId, 'Vendedor no encontrado', { transaction: t });
    const cambios = { actualizadoPor: usuarioId };
    if (datos.nombreNegocio) cambios.nombreNegocio = datos.nombreNegocio.trim();
    if (datos.descripcion !== undefined) cambios.descripcion = datos.descripcion;
    if (datos.categoria) Object.assign(cambios, CatalogoService.categoriaParaGuardar(datos.categoria));
    if (datos.costoDelivery !== undefined) cambios.costoDelivery = Number(datos.costoDelivery);
    if (datos.radioCobertura) cambios.radioCobertura = Number(datos.radioCobertura);
    if (datos.abiertoAhora !== undefined) cambios.abiertoAhora = datos.abiertoAhora === true || datos.abiertoAhora === 'true';
    await vendedor.update(cambios, { transaction: t });
    if (datos.horarioApertura || datos.horarioCierre) {
      await fijarHorario(vendedor.id, datos.horarioApertura || null, datos.horarioCierre || null, usuarioId, t);
    }
  }, { usuarioId });
  auditar({ usuarioId, accion: 'NEGOCIOACTUALIZADO', entidad: 'TNEGOCIOS', req });
  return { vendedor: await aApi(await delUsuario(usuarioId), req, { privado: true }) };
}

async function eliminar(usuarioId, req) {
  const vendedor = await delUsuario(usuarioId);
  await withTransaction((t) => vendedor.destroy({ transaction: t }), { usuarioId });     // borrado lógico (ELIMINADOEN)
  auditar({ usuarioId, accion: 'NEGOCIOELIMINADO', entidad: 'TNEGOCIOS', entidadId: vendedor.id, req });
}

// El local del negocio es una dirección de la persona de tipo LOC: se actualiza la vigente o se crea la primera.
async function actualizarUbicacion(usuarioId, latitud, longitud) {
  const lat = Number(latitud);
  const lng = Number(longitud);
  await withTransaction(async (t) => {
    const vendedor = await delUsuario(usuarioId, 'Vendedor no encontrado', { transaction: t });
    if (vendedor.local) {
      await vendedor.local.update({ latitud: lat, longitud: lng, actualizadoPor: usuarioId }, { transaction: t });
      return;
    }
    const local = await Direccion.create({
      personaId: vendedor.usuario.personaId, tipo: 'LOC', nombre: 'Local', direccion: `Local de ${vendedor.nombreNegocio}`,
      latitud: lat, longitud: lng, creadoPor: usuarioId,
    }, { transaction: t });
    await vendedor.update({ direccionId: local.id, actualizadoPor: usuarioId }, { transaction: t });
  }, { usuarioId });
  return { latitud: lat, longitud: lng };
}

// campo: 'logo' | 'banner'. Recibe la imagen en base64, la optimiza y guarda su código en ARCHIVOS.
async function cambiarImagen(usuarioId, campo, base64, req) {
  const vendedor = await delUsuario(usuarioId);
  const archivo = await ArchivoService.guardarBase64({ base64, categoria: campo.toUpperCase(), propietario: usuarioId });
  await withTransaction((t) => vendedor.update({ [`${campo}Id`]: archivo.id, actualizadoPor: usuarioId }, { transaction: t }), { usuarioId });
  return (await ArchivoService.mapaUrls(req, [archivo.id]))[archivo.id].url;
}

module.exports = { listar, obtener, miPerfil, crear, crearPerfil, actualizar, eliminar, actualizarUbicacion, cambiarImagen, aApi, VISIBLE };
