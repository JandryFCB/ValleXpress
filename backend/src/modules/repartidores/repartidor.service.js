const { Op } = require('sequelize');
const { Repartidor, RepartidorEstado, Ubicacion } = require('./repartidor.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { auditar, logMensaje } = require('../../shared/services/log.service');
const { normalizarPlaca } = require('../../shared/utils/normalizers');
const {
  APROBACION, APROBACIONAAPI, TIPOVEHICULO, VEHICULOAAPI, APIAVEHICULO, VEHICULOSINPLACA, ESTADOPEDIDO: E, vehiculoACodigo,
} = require('../../shared/constants/codigos');

// Lógica del REPARTIDOR: su perfil (vehículo y placa), estar en línea y su ubicación en vivo.
// Las acciones sobre un pedido (aceptar, recoger, entregar) están en pedido.service: aquí no se duplican.

const num = (v) => (v === null || v === undefined ? null : Number(v));
const PLACA = /^[A-Z]{2,3}\d{3,4}[A-Z]?$/;
const ENCURSO = [E.ENCAMINO, E.RECOGIDO];
const INTERVALOGUARDADO = 15 * 1000;        // un punto del recorrido cada 15 s por pedido (el mapa en vivo va aparte)

// El vehículo puede llegar como texto de la API ('moto'), como lo escribe el registro ('Moto', 'Bicicleta') o como código
function vehiculoDe(valor) {
  const t = String(valor || '').trim().toLowerCase();
  if (APIAVEHICULO[t]) return APIAVEHICULO[t];
  if (Object.values(TIPOVEHICULO).includes(t)) return t;
  return vehiculoACodigo(t);
}

// Valida y normaliza la placa según el vehículo (bici y a pie no llevan placa)
function placaPara(vehiculo, placa) {
  if (VEHICULOSINPLACA.includes(vehiculo)) return null;
  const p = normalizarPlaca(placa);
  if (!p) throw AppError.badRequest('Escribe la placa de tu vehículo', 'PLACAREQUERIDA');
  if (!PLACA.test(p)) throw AppError.badRequest('La placa no es válida (ej: ABC-1234 o AB-123C)', 'PLACAINVALIDA');
  return p;
}

async function exigirPlacaLibre(placa, usuarioId, opciones = {}) {
  if (!placa) return;
  const otro = await Repartidor.findOne({ where: { placa, usuarioId: { [Op.ne]: usuarioId } }, ...opciones });
  if (otro) throw AppError.conflict('Esta placa ya está registrada por otro repartidor', 'PLACADUPLICADA');
}

function aApi(r) {
  const e = r.estado || {};
  return {
    usuario: r.usuarioId,
    nombre: r.usuario?.nombre,
    apellido: r.usuario?.apellido,
    vehiculo: VEHICULOAAPI[r.vehiculo],
    placa: r.placa,
    color: r.color,
    aprobacion: APROBACIONAAPI[r.aprobacion],
    disponible: e.disponible === true,
    calificacion: num(e.calificacion) ?? 0,
    numeroCalificaciones: e.numeroCalificaciones ?? 0,
    numeroEntregas: e.numeroEntregas ?? 0,
    ubicacion: e.latitud != null ? { latitud: num(e.latitud), longitud: num(e.longitud), fecha: e.ubicacionEn } : null,
  };
}

const INCLUIR = [{ model: RepartidorEstado, as: 'estado' }, { association: 'usuario', attributes: ['id', 'nombre', 'apellido'] }];
const cargar = (usuarioId, opciones = {}) => Repartidor.findOne({ where: { usuarioId }, include: INCLUIR, ...opciones });

async function exigirPerfil(usuarioId, opciones = {}) {
  const r = await cargar(usuarioId, opciones);
  if (!r) throw AppError.notFound('Aún no tienes tu perfil de repartidor', 'REPARTIDORNOENCONTRADO');
  return r;
}

function exigirAprobado(r) {
  if (r.aprobacion !== APROBACION.APROBADO) throw AppError.forbidden('Tu cuenta de repartidor aún no está aprobada', 'REPARTIDORNOAPROBADO');
}

// ---------------------------------------------------------------------------------------------
// Perfil
// ---------------------------------------------------------------------------------------------
// Lo usa el registro (dentro de su transacción) y POST /api/repartidor. Mientras no haya panel de administración,
// nace aprobado si APROBACIONAUTOMATICA está activa (igual que los negocios).
async function crearPerfil(usuarioId, datos, opciones = {}) {
  const vehiculo = vehiculoDe(datos.vehiculo) || (datos.placa ? TIPOVEHICULO.MOTOCICLETA : TIPOVEHICULO.APIE);
  const placa = placaPara(vehiculo, datos.placa);
  await exigirPlacaLibre(placa, usuarioId, opciones);
  const automatica = (await ConfiguracionService.obtener('APROBACIONAUTOMATICA', true)) === true;
  return Repartidor.create({
    usuarioId,
    vehiculo,
    placa,
    color: datos.color?.trim() || null,
    aprobacion: automatica ? APROBACION.APROBADO : APROBACION.PENDIENTE,
    aprobadoEn: automatica ? new Date() : null,
  }, opciones);
}

async function crear(usuarioId, datos, req) {
  if (await cargar(usuarioId)) throw AppError.conflict('Ya tienes tu perfil de repartidor', 'REPARTIDOREXISTENTE');
  await withTransaction((t) => crearPerfil(usuarioId, datos, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'REPARTIDORCREADO', entidad: 'REPARTIDORES', entidadId: usuarioId, req });
  return aApi(await cargar(usuarioId));
}

const miPerfil = async (usuarioId) => aApi(await exigirPerfil(usuarioId));

async function actualizar(usuarioId, datos, req) {
  const r = await exigirPerfil(usuarioId);
  const vehiculo = datos.vehiculo !== undefined ? vehiculoDe(datos.vehiculo) : r.vehiculo;
  if (!vehiculo) throw AppError.badRequest('Tipo de vehículo inválido', 'VEHICULOINVALIDO');
  const placa = placaPara(vehiculo, datos.placa !== undefined ? datos.placa : r.placa);
  await exigirPlacaLibre(placa, usuarioId);
  const cambios = { vehiculo, placa };
  if (datos.color !== undefined) cambios.color = datos.color?.trim() || null;
  await withTransaction((t) => r.update(cambios, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'REPARTIDORACTUALIZADO', entidad: 'REPARTIDORES', entidadId: usuarioId, detalle: cambios, req });
  return aApi(await cargar(usuarioId));
}

// En línea = recibe avisos de pedidos listos y puede aceptarlos. Solo un repartidor aprobado puede conectarse.
async function cambiarDisponibilidad(usuarioId, disponible, req) {
  const r = await exigirPerfil(usuarioId);
  if (disponible) exigirAprobado(r);
  await RepartidorEstado.update({ disponible, ultimoCambio: new Date() }, { where: { usuarioId } });
  auditar({ usuarioId, accion: disponible ? 'REPARTIDORENLINEA' : 'REPARTIDORFUERADELINEA', entidad: 'REPARTIDORES', entidadId: usuarioId, req });
  return aApi(await cargar(usuarioId));
}

// ---------------------------------------------------------------------------------------------
// Ubicación en vivo
// ---------------------------------------------------------------------------------------------
const ultimoGuardado = new Map();       // pedido -> momento del último punto guardado

// Guarda la posición actual y la reenvía SOLO al cliente y al dueño del negocio de sus entregas en curso.
// Cada 15 s deja además un punto del recorrido. Devuelve cuántas entregas en curso recibieron la ubicación.
async function registrarUbicacion(usuarioId, { lat, lng, precision, velocidad, rumbo }, io) {
  const ahora = new Date();
  await RepartidorEstado.update({ latitud: lat, longitud: lng, ubicacionEn: ahora }, { where: { usuarioId } });

  const { Pedido } = require('../pedidos/pedido.model');         // perezoso: pedido.model también usa este módulo
  const { Negocio } = require('../negocios/negocio.model');
  const entregas = await Pedido.findAll({
    where: { repartidorId: usuarioId, estado: { [Op.in]: ENCURSO } },
    attributes: ['id', 'clienteId', 'negocioId'],
    include: [{ model: Negocio, as: 'negocio', attributes: ['id', 'duenoId'] }],
  });
  const velocidadKmh = velocidad != null ? Math.max(0, Number(velocidad) * 3.6) : null;   // el GPS la da en m/s
  for (const p of entregas) {
    const evento = { pedidoId: Number(p.id), latitud: lat, longitud: lng, rumbo: rumbo ?? null, velocidadKmh, fecha: ahora };
    if (io) for (const u of [p.clienteId, p.negocio?.duenoId, usuarioId]) io.to(`user:${u}`).emit('pedido:ubicacion', evento);
    if (Date.now() - (ultimoGuardado.get(String(p.id)) || 0) >= INTERVALOGUARDADO) {
      ultimoGuardado.set(String(p.id), Date.now());
      Ubicacion.create({ usuarioId, pedidoId: p.id, latitud: lat, longitud: lng, precision: precision ?? null, velocidadKmh, rumbo: rumbo ?? null })
        .catch((e) => logMensaje({ nivel: 'ADVERTENCIA', modulo: 'REPARTIDORES', accion: 'UBICACIONNOGUARDADA', mensaje: 'No se pudo guardar el punto del recorrido', detalle: { error: e.message }, usuarioId, pedidoId: p.id }));
    }
  }
  if (ultimoGuardado.size > 1000) ultimoGuardado.clear();
  return { entregas: entregas.length };
}

// Recorrido guardado de una entrega (para dibujar la ruta)
async function recorrido(pedidoId) {
  const puntos = await Ubicacion.findAll({ where: { pedidoId }, order: [['registradoEn', 'ASC']], attributes: ['latitud', 'longitud', 'registradoEn'], limit: 500 });
  return puntos.map((u) => ({ latitud: num(u.latitud), longitud: num(u.longitud), fecha: u.registradoEn }));
}

module.exports = {
  crearPerfil, crear, miPerfil, actualizar, cambiarDisponibilidad, registrarUbicacion, recorrido,
  exigirPerfil, exigirAprobado, cargar, aApi, vehiculoDe, ENCURSO,
};
