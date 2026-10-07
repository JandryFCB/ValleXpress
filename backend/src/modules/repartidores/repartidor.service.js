const { Op } = require('sequelize');
const Repartidor = require('./repartidor.model');
const Usuario = require('../auth/usuario.model');
const Pedido = require('../pedidos/pedido.model');
const Vendedor = require('../vendedores/vendedor.model');
const PedidoService = require('../pedidos/pedido.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const CatalogoService = require('../../shared/services/catalogo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { auditar } = require('../../shared/services/log.service');
const { normalizarPlaca } = require('../../shared/utils/normalizers');
const { ESTADOPEDIDO: E, APROBACION, vehiculoACodigo } = require('../../shared/constants/codigos');

// Lógica de negocio de los repartidores. El controller solo llama a estos métodos.
// Las acciones sobre un pedido (aceptar, recoger, entregar) las hace pedido.service: aquí no se duplican.

const num = (v) => (v === null || v === undefined ? null : Number(v));
const capitalizar = (t) => (t ? t.charAt(0).toUpperCase() + t.slice(1).toLowerCase() : t);
const DATOSPERSONA = ['id', 'nombre', 'apellido', 'telefono'];
const ACTIVOS = [E.ENCAMINO, E.RECOGIDO];                             // entregas en curso

// El vehículo es texto libre en la app ("Moto"); la BD usa el catálogo TIPOVEHICULO. Si el texto no coincide con
// ninguno, se guarda sin código y el texto original queda en DATOSEXTRA ("vehiculo=Patineta") para devolverlo igual.
function vehiculoParaGuardar(texto) {
  const codigo = vehiculoACodigo(texto);
  const limpio = String(texto || '').trim();
  return { vehiculo: codigo, datosExtra: codigo || !limpio ? null : `vehiculo=${limpio}`.slice(0, 250) };
}
async function vehiculoTexto(r) {
  if (r.datosExtra && r.datosExtra.startsWith('vehiculo=')) return r.datosExtra.slice('vehiculo='.length);
  return r.vehiculo ? capitalizar((await CatalogoService.mapa('tipovehiculo'))[r.vehiculo]) : null;
}

// privado=true agrega el correo del propio repartidor; el público/otros roles no ven datos de contacto
async function aApi(entrada, req, { privado = false } = {}) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  const urls = await ArchivoService.mapaUrls(req, lista.map((r) => r.fotoId));
  const salida = await Promise.all(lista.map(async (r) => ({
    id: r.id,
    usuarioId: r.usuarioId,
    vehiculo: await vehiculoTexto(r),
    vehiculoCodigo: r.vehiculo,
    placa: r.placa,
    licencia: r.licencia,
    calificacionPromedio: num(r.calificacionPromedio),
    totalCalificaciones: r.totalCalificaciones,
    disponible: r.disponible,
    enServicio: r.enServicio,
    latitud: num(r.latitud),
    longitud: num(r.longitud),
    pedidosCompletados: r.pedidosCompletados,
    foto: urls[r.fotoId]?.url || null,
    aprobacion: r.aprobacion,
    ...(r.usuario && { usuario: privado ? { id: r.usuario.id, nombre: r.usuario.nombre, apellido: r.usuario.apellido, email: r.usuario.email, telefono: r.usuario.telefono } : { id: r.usuario.id, nombre: r.usuario.nombre, apellido: r.usuario.apellido } }),
  })));
  return Array.isArray(entrada) ? salida : salida[0];
}

const INCLUIR = [{ model: Usuario, as: 'usuario', attributes: ['id', 'nombre', 'apellido', 'email', 'telefono'] }];

async function delUsuario(usuarioId, mensaje = 'Repartidor no encontrado', opciones = {}) {
  const r = await Repartidor.findOne({ where: { usuarioId }, include: INCLUIR, ...opciones });
  if (!r) throw AppError.notFound(mensaje, 'REPARTIDORNOENCONTRADO');
  return r;
}
const exigirAprobado = (r) => {
  if (r.aprobacion !== APROBACION.APROBADO) throw AppError.forbidden('Tu cuenta de repartidor aún no está aprobada', 'REPARTIDORNOAPROBADO');
};

// Crea el perfil de repartidor (lo usa el registro y POST /repartidores). La licencia es opcional: se completa luego.
async function crearPerfil(usuarioId, datos, { transaction } = {}) {
  const estado = await ConfiguracionService.aprobacionInicial();
  return Repartidor.create({
    usuarioId,
    ...vehiculoParaGuardar(datos.vehiculo),
    placa: datos.placa ? normalizarPlaca(datos.placa) : null,
    licencia: datos.licencia ? String(datos.licencia).trim().toUpperCase() : null,
    disponible: false,
    aprobacion: estado.aprobacion,
    aprobadoEn: estado.aprobadoEn,
    creadoPor: usuarioId,
  }, { transaction });
}

async function crear(usuarioId, datos, req) {
  if (await Repartidor.findOne({ where: { usuarioId } })) throw AppError.conflict('Ya tienes un perfil de repartidor registrado', 'REPARTIDOREXISTENTE');
  const placa = normalizarPlaca(datos.placa);
  if (await Repartidor.findOne({ where: { placa }, paranoid: false })) throw AppError.conflict('Esta placa ya está registrada por otro repartidor', 'PLACADUPLICADA');
  const nuevo = await withTransaction((t) => crearPerfil(usuarioId, datos, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'REPARTIDORCREADO', entidad: 'REPARTIDORES', entidadId: nuevo.id, req });
  return { repartidor: await aApi(await delUsuario(usuarioId), req, { privado: true }) };
}

const miPerfil = async (usuarioId, req) =>
  ({ repartidor: await aApi(await delUsuario(usuarioId, 'No tienes un perfil de repartidor registrado'), req, { privado: true }) });

async function actualizar(usuarioId, datos, req) {
  const r = await delUsuario(usuarioId);
  const cambios = { actualizadoPor: usuarioId };
  if (datos.vehiculo) Object.assign(cambios, vehiculoParaGuardar(datos.vehiculo));
  if (datos.placa) {
    const placa = normalizarPlaca(datos.placa);
    if (placa !== r.placa && await Repartidor.findOne({ where: { placa }, paranoid: false })) {
      throw AppError.conflict('Esta placa ya está registrada por otro repartidor', 'PLACADUPLICADA');
    }
    cambios.placa = placa;
  }
  if (datos.licencia) cambios.licencia = String(datos.licencia).trim().toUpperCase();
  await withTransaction((t) => r.update(cambios, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'REPARTIDORACTUALIZADO', entidad: 'REPARTIDORES', entidadId: r.id, req });
  return { repartidor: await aApi(await delUsuario(usuarioId), req, { privado: true }) };
}

async function cambiarFoto(usuarioId, base64, req) {
  const r = await delUsuario(usuarioId);
  const archivo = await ArchivoService.guardarBase64({ base64, categoria: 'PERFIL', propietario: usuarioId });
  await withTransaction((t) => r.update({ fotoId: archivo.id, actualizadoPor: usuarioId }, { transaction: t }), { usuarioId });
  return (await ArchivoService.mapaUrls(req, [archivo.id]))[archivo.id].url;
}

// Disponible = quiere recibir avisos de pedidos listos. Solo un repartidor aprobado puede activarlo.
async function cambiarDisponibilidad(usuarioId, disponible, req) {
  const r = await delUsuario(usuarioId);
  if (disponible) exigirAprobado(r);
  await withTransaction((t) => r.update({ disponible, actualizadoPor: usuarioId }, { transaction: t }), { usuarioId });
  return { disponible, repartidor: await aApi(r, req, { privado: true }) };
}

// Posición actual (por REST). Se avisa SOLO a quienes siguen sus entregas en curso (sala del pedido); antes se
// emitía a TODOS los clientes conectados.
async function actualizarUbicacion(usuarioId, { latitud, longitud }, req) {
  const r = await delUsuario(usuarioId);
  await r.update({ latitud: Number(latitud), longitud: Number(longitud), ubicacionEn: new Date() });    // columnas volátiles: no generan versiones
  if (req.io) {
    const activos = await Pedido.findAll({ where: { repartidorId: r.id, estado: { [Op.in]: ACTIVOS } }, attributes: ['id'] });
    for (const p of activos) req.io.to(`pedido:${p.id}`).emit('pedido:ubicacion', { pedidoId: p.id, lat: Number(latitud), lng: Number(longitud), ts: Date.now(), repartidorUsuarioId: usuarioId, source: 'live' });
  }
  return { latitud: Number(latitud), longitud: Number(longitud) };
}

// Solo ve dónde está un repartidor: él mismo, o el cliente o el vendedor de un pedido SUYO que va en curso.
async function ubicacion(usuario, repartidorId) {
  const r = await Repartidor.findOne({ where: { id: repartidorId }, attributes: ['id', 'usuarioId', 'latitud', 'longitud'] });
  let permitido = !!r && r.usuarioId === usuario.id;
  if (r && !permitido) {
    const entrega = await Pedido.findOne({
      where: { repartidorId: r.id, estado: { [Op.in]: ACTIVOS } },
      include: [{ model: Vendedor, as: 'vendedor', attributes: ['usuarioId'] }],
    });
    permitido = !!entrega && (entrega.clienteId === usuario.id || entrega.vendedor?.usuarioId === usuario.id);
  }
  if (!permitido) throw AppError.notFound('Repartidor no encontrado', 'REPARTIDORNOENCONTRADO');
  if (r.latitud == null || r.longitud == null) throw AppError.notFound('Ubicación no disponible', 'UBICACIONNODISPONIBLE');
  return { repartidorId: r.id, lat: num(r.latitud), lng: num(r.longitud) };
}

// ---- Pedidos desde el punto de vista del repartidor ----
async function pedidos(where, usuarioId, req, { ocultarCliente = false, limite = 200 } = {}) {
  const lista = await Pedido.findAll({ where, include: PedidoService.INCLUIR, order: PedidoService.ORDEN, limit: limite });
  return { lista: await PedidoService.aApi(lista, req, { ocultarCliente }), usuarioId };
}

// Pedidos LISTOS sin repartidor (sin el teléfono del cliente hasta que acepte)
async function pendientes(usuarioId, req) {
  exigirAprobado(await delUsuario(usuarioId));
  return { pedidos: (await pedidos({ estado: E.LISTO, repartidorId: null }, usuarioId, req, { ocultarCliente: true })).lista };
}

// Pedidos que se están preparando (aviso anticipado para el repartidor)
async function pedidosVista(usuarioId, req) {
  exigirAprobado(await delUsuario(usuarioId));
  return { pedidos: (await pedidos({ estado: { [Op.in]: [E.CONFIRMADO, E.PREPARANDO] } }, usuarioId, req, { ocultarCliente: true })).lista };
}

async function misPedidos(usuarioId, req) {
  const r = await delUsuario(usuarioId);
  return { pedidos: (await pedidos({ repartidorId: r.id }, usuarioId, req)).lista };
}

async function entregasActivas(usuarioId, req) {
  const r = await delUsuario(usuarioId);
  return { entregas: (await pedidos({ repartidorId: r.id, estado: { [Op.in]: ACTIVOS } }, usuarioId, req)).lista };
}

// Ruta heredada PUT /pedidos/:id/estado { estado: 'en_camino' | 'entregado' }. Con el flujo actual el repartidor ya
// queda "en camino" al aceptar, así que 'en_camino' significa "recogí el pedido y voy hacia el cliente" (recogido).
async function cambiarEstadoPedido(usuario, id, estado, req) {
  const pedidoAntes = await Pedido.findOne({ where: { id }, attributes: ['id', 'estado', 'repartidorId'], include: [{ model: Repartidor, as: 'repartidor', attributes: ['usuarioId'] }] });
  if (!pedidoAntes || pedidoAntes.repartidor?.usuarioId !== usuario.id) throw AppError.notFound('Pedido no encontrado', 'PEDIDONOENCONTRADO');

  if (estado === 'en_camino' && pedidoAntes.estado === E.ENCAMINO) await PedidoService.marcarRecogido(usuario, id, req);
  else if (estado === 'entregado') await PedidoService.marcarEntregado(usuario, id, req);
  else if (!(estado === 'en_camino' && pedidoAntes.estado === E.RECOGIDO)) {      // ya estaba recogido: no hay nada que hacer
    throw AppError.conflict('El pedido no puede pasar a ese estado desde su estado actual', 'TRANSICIONINVALIDA');
  }
  return { pedido: await PedidoService.aApi(await PedidoService.cargar(id), req) };
}

// Solo vendedores (y administradores): repartidores disponibles, sin datos de contacto
async function listarDisponibles(req) {
  const lista = await Repartidor.findAll({ where: { disponible: true, aprobacion: APROBACION.APROBADO, activo: true }, include: [{ model: Usuario, as: 'usuario', attributes: ['id', 'nombre', 'apellido'] }] });
  return { repartidores: await aApi(lista, req) };
}

// Solo administradores: todos los repartidores con datos de contacto
async function listar(req) {
  const lista = await Repartidor.findAll({ include: INCLUIR, order: [['creadoEn', 'DESC']] });
  return { repartidores: await aApi(lista, req, { privado: true }) };
}

module.exports = {
  crearPerfil, crear, miPerfil, actualizar, cambiarFoto, cambiarDisponibilidad, actualizarUbicacion, ubicacion,
  pendientes, pedidosVista, misPedidos, entregasActivas, cambiarEstadoPedido, listarDisponibles, listar,
};
