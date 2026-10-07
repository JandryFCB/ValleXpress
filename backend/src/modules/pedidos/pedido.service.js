const { Op } = require('sequelize');
const { sequelize } = require('../../config/database');
const Pedido = require('./pedido.model');
const Calificacion = require('./calificacion.model');
const DetallePedido = require('../shared/detallePedido.model');
const Producto = require('../productos/producto.model');
const Vendedor = require('../vendedores/vendedor.model');
const Repartidor = require('../repartidores/repartidor.model');
const Usuario = require('../auth/usuario.model');
const Direccion = require('../direcciones/direccion.model');
const NotificacionService = require('../notificaciones/notificacion.service');
const { validarTransicion, cambiosDe } = require('./pedido_estado.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const CatalogoService = require('../../shared/services/catalogo.service');
const { auditar } = require('../../shared/services/log.service');
const {
  ESTADOPEDIDO: E, ESTADOPRODUCTO, APROBACION, ESTADOPEDIDOAAPI, METODOPAGOAAPI, APIAMETODOPAGO, APIAESTADOPEDIDO,
} = require('../../shared/constants/codigos');

// Lógica de negocio de los pedidos. El controller solo llama a estos métodos.
//   * Los precios y totales SIEMPRE salen de la BD (el cliente no puede fijarlos).
//   * El vendedor se deduce de los productos; todos deben ser del mismo negocio.
//   * Cada cambio de estado pasa por la máquina de estados (pedido_estado.service.js).
//   * El stock se descuenta al pedir y se devuelve si se cancela o se rechaza (con bloqueo de filas: sin carreras).

const num = (v) => (v === null || v === undefined ? null : Number(v));
const centavos = (v) => Math.round(Number(v) * 100);
const dinero = (c) => c / 100;
const DATOSPERSONA = ['id', 'nombre', 'apellido', 'telefono'];                    // nunca el correo

const INCLUIR = [
  { model: Usuario, as: 'cliente', attributes: DATOSPERSONA },
  { model: Vendedor, as: 'vendedor', include: [{ model: Usuario, as: 'usuario', attributes: DATOSPERSONA }] },
  { model: Repartidor, as: 'repartidor', required: false, include: [{ model: Usuario, as: 'usuario', attributes: DATOSPERSONA }] },
  { model: DetallePedido, as: 'detalles', required: false, include: [{ model: Producto, as: 'producto' }] },
];
const ORDEN = [['creadoEn', 'DESC'], [{ model: DetallePedido, as: 'detalles' }, 'id', 'ASC']];

// ---------------------------------------------------------------------------------------------
// Formato que consume la app (mismas claves que antes; sin correos de otras personas)
// ---------------------------------------------------------------------------------------------
const persona = (u, ocultarTelefono = false) => u && { id: u.id, nombre: u.nombre, apellido: u.apellido, ...(!ocultarTelefono && { telefono: u.telefono }) };

async function aApi(entrada, req, { ocultarCliente = false } = {}) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  const imagenes = lista.flatMap((p) => [p.vendedor?.logoId, ...(p.detalles || []).map((d) => d.producto?.imagenId)]);
  const urls = await ArchivoService.mapaUrls(req, imagenes);
  const salida = lista.map((p) => ({
    id: p.id,
    numeroPedido: p.id,
    clienteId: p.clienteId,
    vendedorId: p.vendedorId,
    repartidorId: p.repartidorId,
    direccionEntregaId: p.direccionEntregaId,
    estado: ESTADOPEDIDOAAPI[p.estado],
    estadoCodigo: p.estado,
    subtotal: num(p.subtotal),
    costoDelivery: num(p.costoDelivery),
    total: num(p.total),
    metodoPago: METODOPAGOAAPI[p.metodoPago],
    pagado: p.pagado,
    notasCliente: p.notasCliente,
    tiempoEstimado: p.tiempoEstimado,
    motivoCancelacion: p.motivoCancel,
    fechaPedido: p.fechaPedido,
    fechaConfirmacion: p.fechaConfirmacion,
    fechaPreparacion: p.fechaPreparacion,
    fechaListo: p.fechaListo,
    fechaAsignacion: p.fechaAsignacion,
    fechaRecogida: p.fechaRecogida,
    fechaEntrega: p.fechaEntrega,
    fechaRecibido: p.fechaRecibido,
    createdAt: p.creadoEn,
    cliente: persona(p.cliente, ocultarCliente),
    vendedor: p.vendedor && {
      id: p.vendedor.id, nombreNegocio: p.vendedor.nombreNegocio, latitud: num(p.vendedor.latitud), longitud: num(p.vendedor.longitud),
      logo: urls[p.vendedor.logoId]?.url || null, usuario: persona(p.vendedor.usuario),
    },
    repartidor: p.repartidor && { id: p.repartidor.id, placa: p.repartidor.placa, usuario: persona(p.repartidor.usuario) },
    direccionEntrega: p.domicilio ? { id: p.direccionEntregaId, direccion: p.domicilio, latitud: num(p.latitudEntrega), longitud: num(p.longitudEntrega) } : null,
    detalles: (p.detalles || []).map((d) => ({
      id: Number(d.id), pedidoId: d.pedidoId, productoId: d.productoId, nombre: d.nombre, cantidad: d.cantidad,
      precioUnitario: num(d.precioUnitario), subtotal: num(d.subtotal), notas: d.notas,
      producto: d.producto && { id: d.producto.id, nombre: d.producto.nombre, precio: num(d.producto.precio), imagen: urls[d.producto.imagenId]?.url || null },
    })),
  }));
  return Array.isArray(entrada) ? salida : salida[0];
}

const cargar = (id) => Pedido.findOne({ where: { id }, include: INCLUIR, order: ORDEN });

function paginar(query) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(50, Math.max(1, parseInt(query.limit, 10) || 20));
  return { page, limit, offset: (page - 1) * limit };
}
const paginacion = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit), hasNext: page * limit < total, hasPrev: page > 1 });

// ---------------------------------------------------------------------------------------------
// Utilidades internas
// ---------------------------------------------------------------------------------------------
const bloquear = (id, where, t) => Pedido.findOne({ where: { id, ...where }, transaction: t, lock: t.LOCK.UPDATE });

async function vendedorDe(usuarioId, t) {
  const v = await Vendedor.findOne({ where: { usuarioId }, attributes: ['id', 'usuarioId'], transaction: t });
  if (!v) throw AppError.notFound('Vendedor no encontrado', 'VENDEDORNOENCONTRADO');
  return v;
}
async function repartidorDe(usuarioId, t) {
  const r = await Repartidor.findOne({ where: { usuarioId }, attributes: ['id', 'usuarioId', 'aprobacion'], transaction: t });
  if (!r) throw AppError.notFound('Repartidor no encontrado', 'REPARTIDORNOENCONTRADO');
  return r;
}
const noEncontrado = () => AppError.notFound('Pedido no encontrado', 'PEDIDONOENCONTRADO');

// Devuelve las unidades al stock (cancelación o rechazo). Bloquea los productos en orden para evitar bloqueos cruzados.
async function devolverStock(pedido, t) {
  const detalles = await DetallePedido.findAll({ where: { pedidoId: pedido.id }, transaction: t });
  const ids = detalles.map((d) => d.productoId);
  const productos = await Producto.findAll({ where: { id: ids }, order: [['id', 'ASC']], paranoid: false, transaction: t, lock: t.LOCK.UPDATE });
  for (const p of productos) {
    if (!p.controlaStock) continue;
    const devuelto = detalles.filter((d) => d.productoId === p.id).reduce((s, d) => s + d.cantidad, 0);
    const stock = p.stock + devuelto;
    await p.update({ stock, estado: p.estado === ESTADOPRODUCTO.AGOTADO && stock > 0 ? ESTADOPRODUCTO.DISPONIBLE : p.estado }, { transaction: t });
  }
}

// ¿Hay otro pedido activo del repartidor? (para liberar su marca "en servicio")
const tieneActivos = (repartidorId, excepto, t) => Pedido.count({ where: { repartidorId, id: { [Op.ne]: excepto }, estado: { [Op.in]: [E.ENCAMINO, E.RECOGIDO] } }, transaction: t });

// ---------------------------------------------------------------------------------------------
// Crear pedido
// ---------------------------------------------------------------------------------------------
async function crear(cliente, datos, req) {
  const metodoPago = APIAMETODOPAGO[String(datos.metodoPago).toLowerCase()] || (METODOPAGOAAPI[datos.metodoPago] ? datos.metodoPago : null);
  if (!metodoPago || !(await CatalogoService.mapa('metodopago'))[metodoPago]) {
    throw AppError.badRequest('Método de pago inválido', 'METODOPAGOINVALIDO');
  }

  // Un mismo producto repetido se suma en una sola línea
  const lineas = new Map();
  for (const it of datos.productos) {
    const previo = lineas.get(it.productoId);
    lineas.set(it.productoId, { productoId: it.productoId, cantidad: (previo?.cantidad || 0) + Number(it.cantidad), notas: it.notas ?? previo?.notas ?? null });
  }
  const items = [...lineas.values()];

  const pedido = await withTransaction(async (t) => {
    const ids = items.map((i) => i.productoId).sort();
    const productos = await Producto.findAll({ where: { id: ids }, order: [['id', 'ASC']], transaction: t, lock: t.LOCK.UPDATE });
    const porId = new Map(productos.map((p) => [p.id, p]));
    const faltante = ids.find((id) => !porId.has(id));
    if (faltante) throw AppError.notFound(`Producto ${faltante} no encontrado`, 'PRODUCTONOENCONTRADO');

    // El vendedor se deduce de los productos (nunca del cuerpo de la petición)
    const vendedores = new Set(productos.map((p) => p.vendedorId));
    if (vendedores.size !== 1) throw AppError.badRequest('Todos los productos del pedido deben ser del mismo negocio', 'NEGOCIOSMEZCLADOS');
    const [vendedorId] = vendedores;
    if (datos.vendedorId && datos.vendedorId !== vendedorId) throw AppError.badRequest('Los productos no pertenecen al negocio indicado', 'NEGOCIOINCORRECTO');

    const vendedor = await Vendedor.findOne({ where: { id: vendedorId }, transaction: t });
    if (!vendedor || vendedor.aprobacion !== APROBACION.APROBADO || !vendedor.activo || vendedor.aceptaPedidos === false) {
      throw AppError.conflict('Este negocio no está recibiendo pedidos en este momento', 'NEGOCIONODISPONIBLE');
    }

    // La dirección debe ser del propio cliente; se guarda una COPIA (si la edita luego, el pedido no cambia)
    let direccion = null;
    if (datos.direccionEntregaId) {
      direccion = await Direccion.findOne({ where: { id: datos.direccionEntregaId, usuarioId: cliente.id }, transaction: t });
      if (!direccion) throw AppError.notFound('Dirección no encontrada', 'DIRECCIONNOENCONTRADA');
    }

    let subtotal = 0;
    for (const it of items) {
      const p = porId.get(it.productoId);
      if (p.estado !== ESTADOPRODUCTO.DISPONIBLE && !(p.estado === ESTADOPRODUCTO.AGOTADO && p.controlaStock && p.stock >= it.cantidad)) {
        throw AppError.conflict(`El producto ${p.nombre} no está disponible`, 'PRODUCTONODISPONIBLE', { productoId: p.id });
      }
      if (p.controlaStock && p.stock < it.cantidad) {
        throw new AppError(`Stock insuficiente para ${p.nombre}`, 400, 'STOCK_INSUFICIENTE', { disponible: p.stock, solicitado: it.cantidad, productoId: p.id });
      }
      subtotal += centavos(p.precio) * it.cantidad;
    }

    const nuevo = await Pedido.create({
      clienteId: cliente.id,
      vendedorId,
      direccionEntregaId: direccion?.id || null,
      domicilio: direccion?.direccion || null,
      latitudEntrega: direccion?.latitud ?? null,
      longitudEntrega: direccion?.longitud ?? null,
      subtotal: dinero(subtotal),
      costoDelivery: 0,                       // lo fija el repartidor al aceptar
      total: dinero(subtotal),
      metodoPago,
      notasCliente: datos.notasCliente || null,
      creadoPor: cliente.id,
    }, { transaction: t });

    await DetallePedido.bulkCreate(items.map((it) => {
      const p = porId.get(it.productoId);
      return { pedidoId: nuevo.id, productoId: p.id, nombre: p.nombre, cantidad: it.cantidad, precioUnitario: p.precio, subtotal: dinero(centavos(p.precio) * it.cantidad), notas: it.notas, creadoPor: cliente.id };
    }), { transaction: t });

    for (const it of items) {                  // descuenta el stock de los productos que lo controlan
      const p = porId.get(it.productoId);
      if (!p.controlaStock) continue;
      const stock = p.stock - it.cantidad;
      await p.update({ stock, estado: stock === 0 && p.estado === ESTADOPRODUCTO.DISPONIBLE ? ESTADOPRODUCTO.AGOTADO : p.estado, actualizadoPor: cliente.id }, { transaction: t });
    }
    nuevo.vendedorUsuarioId = vendedor.usuarioId;
    return nuevo;
  }, { usuarioId: cliente.id });

  auditar({ usuarioId: cliente.id, accion: 'PEDIDOCREADO', entidad: 'PEDIDOS', entidadId: pedido.id, req });
  await NotificacionService.notificar({ io: req.io, usuarioId: pedido.vendedorUsuarioId, tipo: 'pedido_nuevo', titulo: '¡Nuevo pedido recibido! 🛒', mensaje: `Tienes un nuevo pedido #${pedido.id}`, pedidoId: pedido.id });
  await NotificacionService.notificar({ io: req.io, usuarioId: cliente.id, tipo: 'pedido_creado', titulo: 'Pedido creado', mensaje: 'Tu pedido fue creado exitosamente', pedidoId: pedido.id, estado: 'pendiente', guardar: false });
  return { pedido: await aApi(await cargar(pedido.id), req) };
}

// ---------------------------------------------------------------------------------------------
// Consultas
// ---------------------------------------------------------------------------------------------
async function listarDelCliente(clienteId, query, req) {
  const pag = paginar(query);
  const { count, rows } = await Pedido.findAndCountAll({ where: { clienteId }, include: INCLUIR, order: ORDEN, limit: pag.limit, offset: pag.offset, distinct: true });
  return { pedidos: await aApi(rows, req), pagination: paginacion(pag, count) };
}

async function listarDelVendedor(usuarioId, query, req) {
  const vendedor = await vendedorDe(usuarioId);
  const pag = paginar(query);
  const { count, rows } = await Pedido.findAndCountAll({ where: { vendedorId: vendedor.id }, include: INCLUIR, order: ORDEN, limit: pag.limit, offset: pag.offset, distinct: true });
  return { pedidos: await aApi(rows, req), pagination: paginacion(pag, count) };
}

// Solo ven un pedido: su cliente, su vendedor y su repartidor. Un repartidor aprobado puede ver los pedidos LISTOS
// sin repartidor (para decidir si los acepta), sin el teléfono del cliente. Cualquier otro: 404.
async function obtener(usuario, id, req) {
  const pedido = await cargar(id);
  if (!pedido) throw noEncontrado();
  const esCliente = pedido.clienteId === usuario.id;
  const esVendedor = pedido.vendedor?.usuarioId === usuario.id;
  const esRepartidor = pedido.repartidor?.usuarioId === usuario.id;
  if (esCliente || esVendedor || esRepartidor) return aApi(pedido, req);

  if (usuario.tipoUsuario === 'repartidor' && pedido.estado === E.LISTO && !pedido.repartidorId) {
    const rep = await Repartidor.findOne({ where: { usuarioId: usuario.id }, attributes: ['aprobacion'] });
    if (rep?.aprobacion === APROBACION.APROBADO) return aApi(pedido, req, { ocultarCliente: true });
  }
  throw noEncontrado();
}

// ---------------------------------------------------------------------------------------------
// Vendedor: confirmar, preparar, dejar listo o rechazar
// ---------------------------------------------------------------------------------------------
async function cambiarEstadoVendedor(usuario, id, { estado, motivo }, req) {
  const siguiente = APIAESTADOPEDIDO[estado];
  const pedido = await withTransaction(async (t) => {
    const vendedor = await vendedorDe(usuario.id, t);
    const p = await bloquear(id, { vendedorId: vendedor.id }, t);
    if (!p) throw noEncontrado();
    validarTransicion(p.estado, siguiente, 'vendedor');
    const extra = { actualizadoPor: usuario.id };
    if (siguiente === E.RECHAZADO) {
      Object.assign(extra, { motivoCancel: motivo || null, canceladoPor: usuario.id });
      await devolverStock(p, t);
    }
    await p.update({ ...cambiosDe(siguiente), ...extra }, { transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: `PEDIDO${estado.toUpperCase()}`, entidad: 'PEDIDOS', entidadId: id, req });
  if (siguiente === E.LISTO) {
    await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo: 'pedido_listo', titulo: '¡Tu pedido está listo! 🍽️', mensaje: `Tu pedido #${pedido.id} está listo y pronto será asignado a un repartidor`, pedidoId: pedido.id });
    const repartidores = await Repartidor.findAll({ where: { disponible: true, aprobacion: APROBACION.APROBADO, activo: true }, attributes: ['usuarioId'] });
    for (const r of repartidores) {
      await NotificacionService.notificar({ io: req.io, usuarioId: r.usuarioId, tipo: 'pedido_listo', titulo: 'Pedido listo', mensaje: `Pedido listo: ${pedido.id}`, pedidoId: pedido.id, extra: { vendedorId: pedido.vendedorId } });
    }
  } else if (siguiente === E.RECHAZADO) {
    await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo: 'pedido_rechazado', titulo: 'Pedido rechazado', mensaje: `El negocio no pudo atender tu pedido #${pedido.id}${motivo ? `: ${motivo}` : ''}`, pedidoId: pedido.id, estado: 'rechazado' });
  }
  return aApi(await cargar(id), req);
}

// ---------------------------------------------------------------------------------------------
// Cliente: cancelar (solo pendiente), recibir y calificar
// ---------------------------------------------------------------------------------------------
async function cancelar(usuario, id, { motivo } = {}, req) {
  const pedido = await withTransaction(async (t) => {
    const p = await bloquear(id, { clienteId: usuario.id }, t);
    if (!p) throw noEncontrado();
    if (p.estado !== E.PENDIENTE) throw AppError.conflict('No se puede cancelar un pedido que ya está en proceso', 'PEDIDOENPROCESO');
    await devolverStock(p, t);
    await p.update({ ...cambiosDe(E.CANCELADO), motivoCancel: motivo || null, canceladoPor: usuario.id, actualizadoPor: usuario.id }, { transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDOCANCELADO', entidad: 'PEDIDOS', entidadId: id, req });
  const vendedor = await Vendedor.findOne({ where: { id: pedido.vendedorId }, attributes: ['usuarioId'] });
  if (vendedor) await NotificacionService.notificar({ io: req.io, usuarioId: vendedor.usuarioId, tipo: 'pedido_cancelado', titulo: 'Pedido cancelado', mensaje: `El pedido #${pedido.id} fue cancelado por el cliente`, pedidoId: pedido.id, estado: 'cancelado' });
}

async function marcarRecibido(usuario, id, req) {
  const pedido = await withTransaction(async (t) => {
    const p = await bloquear(id, { clienteId: usuario.id }, t);
    if (!p) throw noEncontrado();
    if (p.estado !== E.ENTREGADO) throw AppError.conflict('El pedido debe estar entregado para marcar recibido', 'TRANSICIONINVALIDA');
    validarTransicion(p.estado, E.RECIBIDO, 'cliente');
    await p.update({ ...cambiosDe(E.RECIBIDO), actualizadoPor: usuario.id }, { transaction: t });

    // Contadores del negocio, del repartidor y de los productos
    await Vendedor.increment('totalPedidos', { by: 1, where: { id: p.vendedorId }, transaction: t });
    if (p.repartidorId) await Repartidor.increment('pedidosCompletados', { by: 1, where: { id: p.repartidorId }, transaction: t });
    const detalles = await DetallePedido.findAll({ where: { pedidoId: p.id }, transaction: t });
    for (const d of detalles) await Producto.increment('totalVendidos', { by: d.cantidad, where: { id: d.productoId }, transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDORECIBIDO', entidad: 'PEDIDOS', entidadId: id, req });
  const aviso = { tipo: 'pedido_recibido_cliente', titulo: '¡Pedido recibido por el cliente! ✅', mensaje: `El cliente recibió el pedido #${pedido.id}`, pedidoId: pedido.id };
  const vendedor = await Vendedor.findOne({ where: { id: pedido.vendedorId }, attributes: ['usuarioId'] });
  if (vendedor) await NotificacionService.notificar({ io: req.io, usuarioId: vendedor.usuarioId, ...aviso });
  if (pedido.repartidorId) {
    const rep = await Repartidor.findOne({ where: { id: pedido.repartidorId }, attributes: ['usuarioId'] });
    if (rep) await NotificacionService.notificar({ io: req.io, usuarioId: rep.usuarioId, ...aviso });
  }
  return { pedido: await aApi(await cargar(id), req) };
}

// La app envía { valoracion (1-5), comentario }. Por defecto califica al vendedor; con tipo:'repartidor', al repartidor.
async function calificar(usuario, id, { valoracion, comentario, tipo = 'vendedor' }, req) {
  const pedido = await Pedido.findOne({ where: { id, clienteId: usuario.id } });
  if (!pedido) throw noEncontrado();
  if (![E.ENTREGADO, E.RECIBIDO].includes(pedido.estado)) throw AppError.conflict('Solo puedes calificar un pedido entregado', 'PEDIDONOENTREGADO');
  const TIPO = String(tipo).toUpperCase();
  if (TIPO === 'REPARTIDOR' && !pedido.repartidorId) throw AppError.badRequest('Este pedido no tuvo repartidor', 'SINREPARTIDOR');
  if (await Calificacion.findOne({ where: { pedidoId: id, tipo: TIPO } })) throw AppError.conflict('Ya calificaste este pedido', 'YACALIFICADO');

  await withTransaction(async (t) => {
    await Calificacion.create({
      pedidoId: id, usuarioId: usuario.id, tipo: TIPO, puntuacion: valoracion, comentario: comentario || null,
      vendedorId: TIPO === 'VENDEDOR' ? pedido.vendedorId : null, repartidorId: TIPO === 'REPARTIDOR' ? pedido.repartidorId : null, creadoPor: usuario.id,
    }, { transaction: t });
    const [tabla, columna, valor] = TIPO === 'VENDEDOR' ? ['vendedores', 'vendedor', pedido.vendedorId] : ['repartidores', 'repartidor', pedido.repartidorId];
    await sequelize.query(   // recalcula el promedio y el total de calificaciones (tabla y columna vienen de una lista fija)
      `UPDATE ${tabla} SET
         calificacion = COALESCE((SELECT ROUND(AVG(puntuacion), 2) FROM calificaciones WHERE ${columna} = :valor AND visible AND eliminadoen IS NULL), 0),
         totalcalif   = (SELECT COUNT(*) FROM calificaciones WHERE ${columna} = :valor AND visible AND eliminadoen IS NULL)
       WHERE ${columna} = :valor`,
      { replacements: { valor }, transaction: t },
    );
  }, { usuarioId: usuario.id });
  auditar({ usuarioId: usuario.id, accion: 'PEDIDOCALIFICADO', entidad: 'CALIFICACIONES', entidadId: id, detalle: { tipo: TIPO, valoracion }, req });
}

// ---------------------------------------------------------------------------------------------
// Repartidor: aceptar, (en camino), recoger y entregar
// ---------------------------------------------------------------------------------------------
async function aceptarRepartidor(usuario, id, costoDelivery, req) {
  const pedido = await withTransaction(async (t) => {
    const repartidor = await repartidorDe(usuario.id, t);
    if (repartidor.aprobacion !== APROBACION.APROBADO) throw AppError.forbidden('Tu cuenta de repartidor aún no está aprobada', 'REPARTIDORNOAPROBADO');
    const p = await bloquear(id, {}, t);                        // bloqueo de fila: si dos repartidores aceptan a la vez, solo gana uno
    if (!p) throw noEncontrado();
    if (p.repartidorId) throw AppError.conflict('El pedido ya tiene un repartidor asignado', 'PEDIDOASIGNADO');
    if (p.estado !== E.LISTO) throw AppError.conflict('El pedido debe estar listo para asignar repartidor', 'TRANSICIONINVALIDA');
    validarTransicion(p.estado, E.ENCAMINO, 'repartidor');

    const costo = centavos(costoDelivery);
    const total = centavos(p.subtotal) - centavos(p.descuento || 0) + costo + centavos(p.propina || 0);
    await p.update({ ...cambiosDe(E.ENCAMINO), repartidorId: repartidor.id, costoDelivery: dinero(costo), total: dinero(total), actualizadoPor: usuario.id }, { transaction: t });
    await Repartidor.update({ enServicio: true, actualizadoPor: usuario.id }, { where: { id: repartidor.id }, transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDOACEPTADO', entidad: 'PEDIDOS', entidadId: id, detalle: { costoDelivery }, req });
  await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo: 'pedido_en_camino', titulo: '¡Repartidor asignado! 🚴', mensaje: `Un repartidor aceptó tu pedido #${pedido.id} y va en camino`, pedidoId: pedido.id, estado: 'en_camino', extra: { repartidorId: pedido.repartidorId } });
  return { pedido: await aApi(await cargar(id), req) };
}

// Ruta heredada (PATCH /:id/en-camino): aceptar ya deja el pedido "en camino", así que es idempotente.
async function marcarEnCamino(usuario, id) {
  const repartidor = await repartidorDe(usuario.id);
  const pedido = await Pedido.findOne({ where: { id, repartidorId: repartidor.id } });
  if (!pedido) throw noEncontrado();
  if (pedido.estado !== E.ENCAMINO) throw AppError.conflict('El pedido debe estar listo para marcar en camino', 'TRANSICIONINVALIDA');
}

async function marcarRecogido(usuario, id, req) {
  const pedido = await withTransaction(async (t) => {
    const repartidor = await repartidorDe(usuario.id, t);
    const p = await bloquear(id, { repartidorId: repartidor.id }, t);
    if (!p) throw noEncontrado();
    if (p.estado !== E.ENCAMINO) throw AppError.conflict('El pedido debe estar en camino para marcar como recogido', 'TRANSICIONINVALIDA');
    validarTransicion(p.estado, E.RECOGIDO, 'repartidor');
    await p.update({ ...cambiosDe(E.RECOGIDO), actualizadoPor: usuario.id }, { transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo: 'pedido_recogido', titulo: '¡Tu pedido fue recogido! 🚴', mensaje: `El repartidor recogió tu pedido #${pedido.id} y va en camino`, pedidoId: pedido.id, estado: 'recogido' });
  return { id: pedido.id, estado: 'recogido', fechaRecogida: pedido.fechaRecogida };
}

async function marcarEntregado(usuario, id, req) {
  const pedido = await withTransaction(async (t) => {
    const repartidor = await repartidorDe(usuario.id, t);
    const p = await bloquear(id, { repartidorId: repartidor.id }, t);
    if (!p) throw noEncontrado();
    if (p.estado !== E.RECOGIDO) throw AppError.conflict('El pedido debe estar recogido para marcar entregado', 'TRANSICIONINVALIDA');
    validarTransicion(p.estado, E.ENTREGADO, 'repartidor');
    await p.update({ ...cambiosDe(E.ENTREGADO), actualizadoPor: usuario.id }, { transaction: t });
    if (!(await tieneActivos(repartidor.id, p.id, t))) await Repartidor.update({ enServicio: false, actualizadoPor: usuario.id }, { where: { id: repartidor.id }, transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo: 'pedido_entregado', titulo: '¡Pedido entregado! 🎉', mensaje: `Tu pedido #${pedido.id} fue entregado. Por favor confirma la recepción.`, pedidoId: pedido.id, estado: 'entregado' });
}

module.exports = {
  crear, listarDelCliente, listarDelVendedor, obtener, cambiarEstadoVendedor, cancelar, marcarRecibido, calificar,
  aceptarRepartidor, marcarEnCamino, marcarRecogido, marcarEntregado, aApi, cargar, INCLUIR, ORDEN,
};
