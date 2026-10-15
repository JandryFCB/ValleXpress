const { Op, QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { Pedido, Detalle, Calificacion } = require('./pedido.model');
const { Negocio, NegocioEstado, Horario } = require('../negocios/negocio.model');
const { Producto } = require('../productos/producto.model');
const Direccion = require('../direcciones/direccion.model');
const Usuario = require('../auth/usuario.model');
const NegocioService = require('../negocios/negocio.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const RepartidorService = require('../repartidores/repartidor.service');
const { Repartidor, RepartidorEstado } = require('../repartidores/repartidor.model');
const { ACTIVOS, TERMINADOS, validarTransicion, validarCancelacionAdmin } = require('./pedido_estado.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const { auditar } = require('../../shared/services/log.service');
const { distanciaKm } = require('../../shared/utils/geo');
const {
  ESTADOPEDIDO: E, ESTADOPEDIDOAAPI, APIAESTADOPEDIDO, ESTADOPRODUCTO, APROBACION, METODOPAGOAAPI, APIAMETODOPAGO, VEHICULOAAPI,
} = require('../../shared/constants/codigos');

// Lógica de los PEDIDOS.
//   * Precios, costo de envío y totales SIEMPRE salen de la BD (la app no puede fijarlos).
//   * Un pedido es de UN negocio; el negocio debe estar abierto (interruptor + horario) y aceptando pedidos.
//   * El stock se descuenta al pedir (con un UPDATE atómico: dos clientes no pueden llevarse la última unidad)
//     y se devuelve si el pedido se cancela o se rechaza.
//   * Cada cambio de estado pasa por la máquina de estados y deja su versión en el historial de TPEDIDOS.
//   * Solo ven un pedido su cliente, el dueño del negocio y el repartidor asignado. A cualquier otro: 404.
//     Excepción: un repartidor en línea ve los pedidos LISTOS sin repartidor (sin los datos de contacto del cliente)
//     para decidir si los acepta.
//   * El repartidor tiene una sola entrega en curso a la vez; si dos aceptan el mismo pedido, gana uno (bloqueo de fila).

const num = (v) => (v === null || v === undefined ? null : Number(v));
const centavos = (v) => Math.round(Number(v) * 100);
const dinero = (c) => c / 100;
const noEncontrado = () => AppError.notFound('Pedido no encontrado', 'PEDIDONOENCONTRADO');
const MINUTOSENTREGA = 15;     // se suman al tiempo de preparación del negocio para estimar la entrega

const INCLUIR = [
  { model: Detalle, as: 'detalles', required: false },
  { model: Calificacion, as: 'calificaciones', required: false },
  { model: Negocio, as: 'negocio', include: [{ model: Direccion, as: 'local', required: false }, { model: Usuario, as: 'dueno', attributes: ['id', 'telefono'] }] },
  { model: Usuario, as: 'cliente', attributes: ['id', 'nombre', 'apellido', 'telefono'] },
  { model: Usuario, as: 'repartidor', attributes: ['id', 'nombre', 'apellido', 'telefono'], required: false },
  { model: Repartidor, as: 'perfilRepartidor', required: false, include: [{ model: RepartidorEstado, as: 'estado' }] },
];
const ENCURSO = [E.ENCAMINO, E.RECOGIDO];          // el repartidor ya tiene el pedido
const ORDEN = [['fechaPedido', 'DESC'], [{ model: Detalle, as: 'detalles' }, 'linea', 'ASC']];
const cargar = (id) => Pedido.findOne({ where: { id }, include: INCLUIR, order: ORDEN });

// Línea de tiempo: cuándo entró el pedido a cada estado (sale del historial de TPEDIDOS)
async function lineaDeTiempo(pedidoId) {
  const filas = await sequelize.query(
    'SELECT cestatuspedido AS estado, MIN(fdesde) AS fecha FROM tpedidos WHERE cpedido = :id GROUP BY cestatuspedido ORDER BY fecha',
    { replacements: { id: pedidoId }, type: QueryTypes.SELECT },
  );
  return filas.map((f) => ({ estado: ESTADOPEDIDOAAPI[f.estado], fecha: f.fecha }));
}

// ---------------------------------------------------------------------------------------------
// Formato que recibe la app. rol = quién mira:
//   cliente     -> no recibe sus propios datos de contacto
//   vendedor    -> recibe los del cliente
//   repartidor  -> recibe los del cliente y el teléfono del negocio (solo si es el repartidor asignado)
//   candidato   -> repartidor que todavía no lo acepta: ve a dónde va, pero no quién es el cliente
// ---------------------------------------------------------------------------------------------
const persona = (u) => u && { usuario: u.id, nombre: u.nombre, apellido: u.apellido, telefono: u.telefono };

function repartidorApi(p) {
  if (!p.repartidor) return null;
  const perfil = p.perfilRepartidor;
  const e = perfil?.estado;
  return {
    ...persona(p.repartidor),
    vehiculo: perfil ? VEHICULOAAPI[perfil.vehiculo] : null,
    placa: perfil?.placa || null,
    color: perfil?.color || null,
    calificacion: e ? num(e.calificacion) : null,
    // Ubicación solo mientras lleva el pedido (después ya no es asunto del cliente ni del negocio)
    ubicacion: ENCURSO.includes(p.estado) && e?.latitud != null ? { latitud: num(e.latitud), longitud: num(e.longitud), fecha: e.ubicacionEn } : null,
  };
}

async function aApi(entrada, req, { rol = 'cliente', detalle = false } = {}) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  // Imágenes: logo del negocio y la imagen actual de cada producto (si el producto se borró, ya no tiene)
  const idsProductos = [...new Set(lista.flatMap((p) => (p.detalles || []).map((d) => String(d.productoId))))];
  const productos = idsProductos.length ? await Producto.findAll({ where: { id: idsProductos }, attributes: ['id', 'imagenId'] }) : [];
  const imagenDe = Object.fromEntries(productos.map((p) => [String(p.id), p.imagenId]));
  const urls = await ArchivoService.mapaUrls(req, [...lista.map((p) => p.negocio?.logoId), ...Object.values(imagenDe)]);

  const salida = [];
  for (const p of lista) {
    const n = p.negocio;
    const calif = (destino) => (p.calificaciones || []).find((c) => c.destino === destino);
    const item = {
      id: Number(p.id),
      estado: ESTADOPEDIDOAAPI[p.estado],
      fecha: p.fechaPedido,
      actualizado: p.fDesde,
      negocio: n && {
        id: Number(n.id),
        nombre: n.nombre,
        logo: urls[String(n.logoId)]?.miniatura || null,
        local: n.local ? { direccion: n.local.direccion, referencia: n.local.referencia, latitud: num(n.local.latitud), longitud: num(n.local.longitud) } : null,
        ...((rol === 'repartidor' || rol === 'administrador') && { telefono: n.dueno?.telefono || null }),
      },
      // Distancia del negocio a la entrega (en línea recta): le sirve al repartidor para decidir
      distanciaKm: n?.local ? Number(distanciaKm({ lat: num(n.local.latitud), lng: num(n.local.longitud) }, { lat: num(p.latitud), lng: num(p.longitud) }).toFixed(2)) : null,
      entrega: { direccion: p.direccionEntrega, referencia: p.referenciaEntrega, latitud: num(p.latitud), longitud: num(p.longitud) },
      metodoPago: METODOPAGOAAPI[p.metodoPago],
      pagado: p.pagado,
      subtotal: num(p.subtotal),
      costoEnvio: num(p.costoEnvio),
      descuento: num(p.descuento),
      propina: num(p.propina),
      total: num(p.total),
      notas: p.notas,
      tiempoEstimado: p.tiempoEstimado,
      motivoCancelacion: p.motivoCancelacion,
      productos: (p.detalles || []).map((d) => ({
        linea: d.linea,
        productoId: Number(d.productoId),
        nombre: d.nombre,
        precioUnitario: num(d.precioUnitario),
        cantidad: d.cantidad,
        subtotal: num(d.subtotal),
        notas: d.notas,
        imagen: urls[String(imagenDe[String(d.productoId)])]?.miniatura || null,
      })),
      cantidadProductos: (p.detalles || []).reduce((s, d) => s + d.cantidad, 0),
      repartidor: repartidorApi(p),
      calificacion: calif('NEGOCIO') ? { puntuacion: calif('NEGOCIO').puntuacion, comentario: calif('NEGOCIO').comentario } : null,
      calificacionRepartidor: calif('REPARTIDOR') ? { puntuacion: calif('REPARTIDOR').puntuacion, comentario: calif('REPARTIDOR').comentario } : null,
      ...(['vendedor', 'repartidor', 'administrador'].includes(rol) && { cliente: persona(p.cliente) }),
    };
    if (rol === 'candidato') delete item.calificacion;
    if (detalle) item.lineaTiempo = await lineaDeTiempo(p.id);
    salida.push(item);
  }
  return Array.isArray(entrada) ? salida : salida[0];
}

function paginar(query) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(50, Math.max(1, parseInt(query.limit, 10) || 20));
  return { page, limit, offset: (page - 1) * limit };
}
const paginacion = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit), hasNext: page * limit < total });
const filtroEstado = (estado) => (estado === 'historial' ? { [Op.in]: TERMINADOS } : estado === 'activos' ? { [Op.in]: ACTIVOS } : undefined);

// Lista de pedidos: primero se pagina por códigos (el JOIN con el detalle multiplicaría las filas) y luego se cargan completos
async function listar(where, query, req, rol) {
  const pag = paginar(query);
  const { count, rows } = await Pedido.findAndCountAll({ where, attributes: ['id'], order: [['fechaPedido', 'DESC']], limit: pag.limit, offset: pag.offset });
  const pedidos = rows.length ? await Pedido.findAll({ where: { id: rows.map((r) => r.id) }, include: INCLUIR, order: ORDEN }) : [];
  return { pedidos: await aApi(pedidos, req, { rol }), pagination: paginacion(pag, count) };
}

// ---------------------------------------------------------------------------------------------
// Stock
// ---------------------------------------------------------------------------------------------
// Descuenta unidades solo si alcanzan (UPDATE atómico). Si llega a 0, el producto pasa a "agotado".
async function descontarStock(producto, cantidad, t) {
  const [filas] = await sequelize.query(
    `UPDATE tproductosinventario SET stock = stock - :cantidad, fultimomovimiento = clock_timestamp()
      WHERE cproducto = :id AND stock >= :cantidad RETURNING stock`,
    { replacements: { id: producto.id, cantidad }, transaction: t },
  );
  if (!filas.length) {
    const [[actual]] = await sequelize.query('SELECT stock FROM tproductosinventario WHERE cproducto = :id', { replacements: { id: producto.id }, transaction: t });
    throw AppError.conflict(`No hay suficientes unidades de ${producto.nombre}`, 'STOCKINSUFICIENTE', { productoId: Number(producto.id), disponible: actual?.stock ?? 0 });
  }
  if (filas[0].stock === 0 && producto.estado === ESTADOPRODUCTO.DISPONIBLE) await producto.update({ estado: ESTADOPRODUCTO.AGOTADO }, { transaction: t });
}

// Devuelve las unidades (cancelación o rechazo). Si el producto estaba agotado y vuelve a tener, pasa a "disponible".
async function devolverStock(pedidoId, t) {
  const detalles = await Detalle.findAll({ where: { pedidoId }, order: [['productoId', 'ASC']], transaction: t });
  const productos = await Producto.findAll({ where: { id: detalles.map((d) => d.productoId), controlaStock: true }, transaction: t });
  for (const prod of productos) {
    const unidades = detalles.filter((d) => String(d.productoId) === String(prod.id)).reduce((s, d) => s + d.cantidad, 0);
    await sequelize.query(
      'UPDATE tproductosinventario SET stock = stock + :unidades, fultimomovimiento = clock_timestamp() WHERE cproducto = :id',
      { replacements: { id: prod.id, unidades }, transaction: t },
    );
    if (prod.estado === ESTADOPRODUCTO.AGOTADO) await prod.update({ estado: ESTADOPRODUCTO.DISPONIBLE }, { transaction: t });
  }
}

// ---------------------------------------------------------------------------------------------
// Avisos: notificación guardada + evento en vivo para refrescar las pantallas abiertas
// ---------------------------------------------------------------------------------------------
// repartidores=true avisa también a todos los repartidores conectados (un pedido apareció o dejó de estar libre)
function avisarCambio(io, pedido, duenoId, { repartidores = false } = {}) {
  if (!io) return;
  const evento = { pedidoId: Number(pedido.id), estado: ESTADOPEDIDOAAPI[pedido.estado] };
  for (const u of [pedido.clienteId, duenoId, pedido.repartidorId].filter(Boolean)) io.to(`user:${u}`).emit('pedido:actualizado', evento);
  if (repartidores) io.to('role:repartidor').emit('pedido:actualizado', evento);
  io.to('role:administrador').emit('pedido:actualizado', evento);     // el panel del administrador se refresca solo
}

const AVISOCLIENTE = {
  [E.CONFIRMADO]: ['pedido_confirmado', '¡Pedido confirmado! ✅', (p, n) => `${n} confirmó tu pedido #${p.id}${p.tiempoEstimado ? `. Llega en unos ${p.tiempoEstimado} min` : ''}`],
  [E.PREPARANDO]: ['pedido_preparando', 'Preparando tu pedido 👨‍🍳', (p, n) => `${n} está preparando tu pedido #${p.id}`],
  [E.LISTO]: ['pedido_listo', '¡Tu pedido está listo! 🍽️', (p) => `Tu pedido #${p.id} está listo; pronto saldrá hacia ti`],
  [E.RECHAZADO]: ['pedido_rechazado', 'Pedido rechazado', (p, n) => `${n} no pudo atender tu pedido #${p.id}${p.motivoCancelacion ? `: ${p.motivoCancelacion}` : ''}`],
  [E.ENCAMINO]: ['pedido_en_camino', 'Repartidor asignado 🛵', (p, n, r) => `${r} va a ${n} a recoger tu pedido #${p.id}`],
  [E.RECOGIDO]: ['pedido_recogido', '¡Tu pedido va hacia ti! 🛵', (p, n, r) => `${r} recogió tu pedido #${p.id}. Síguelo en el mapa`],
  [E.ENTREGADO]: ['pedido_entregado', '¡Pedido entregado! 🎉', (p) => `Tu pedido #${p.id} llegó. Confírmalo y califica tu experiencia`],
};

// Avisa a los repartidores en línea y aprobados que hay un pedido listo para recoger
async function avisarRepartidores(io, pedido, negocioNombre) {
  const enLinea = await RepartidorEstado.findAll({ where: { disponible: true }, attributes: ['usuarioId'] });
  const aprobados = enLinea.length
    ? await Repartidor.findAll({ where: { usuarioId: enLinea.map((r) => r.usuarioId), aprobacion: APROBACION.APROBADO }, attributes: ['usuarioId'] })
    : [];
  for (const r of aprobados) {
    await NotificacionService.notificar({
      io, usuarioId: r.usuarioId, tipo: 'pedido_disponible', titulo: 'Pedido listo para recoger 📦',
      mensaje: `${negocioNombre}: pedido #${pedido.id} · ganas $${num(pedido.costoEnvio).toFixed(2)}`, pedidoId: pedido.id, datos: { estado: 'listo' },
    });
  }
}

// ---------------------------------------------------------------------------------------------
// Cliente: crear
// ---------------------------------------------------------------------------------------------
async function metodoActivo(codigo) {
  const [fila] = await sequelize.query(
    "SELECT esactivo FROM tmetodospago WHERE cmetodopago = :c AND cidioma = 'es' AND fhasta = '2999-12-31 00:00:00-05'",
    { replacements: { c: codigo }, type: QueryTypes.SELECT },
  );
  return fila?.esactivo === true;
}

async function crear(cliente, datos, req) {
  const metodoPago = APIAMETODOPAGO[String(datos.metodoPago || '').toLowerCase()];
  if (!metodoPago || !(await metodoActivo(metodoPago))) throw AppError.badRequest('Ese método de pago no está disponible', 'METODOPAGOINVALIDO');

  // El mismo producto repetido se suma en una sola línea
  const lineas = new Map();
  for (const it of datos.productos) {
    const clave = String(it.productoId);
    const previo = lineas.get(clave);
    lineas.set(clave, { productoId: clave, cantidad: (previo?.cantidad || 0) + Number(it.cantidad), notas: it.notas?.trim() || previo?.notas || null });
  }
  const items = [...lineas.values()].sort((a, b) => Number(a.productoId) - Number(b.productoId));   // orden fijo: sin bloqueos cruzados
  if (items.some((i) => i.cantidad > 99)) throw AppError.badRequest('Máximo 99 unidades por producto', 'CANTIDADINVALIDA');

  const { pedido, negocio } = await withTransaction(async (t) => {
    const negocio = await Negocio.findOne({
      where: { id: datos.negocioId },
      include: [{ model: NegocioEstado, as: 'estado' }, { model: Horario, as: 'horarios', required: false }, { model: Direccion, as: 'local', required: false }],
      transaction: t,
    });
    if (!negocio || negocio.aprobacion !== APROBACION.APROBADO) throw AppError.notFound('Negocio no encontrado', 'NEGOCIONOENCONTRADO');
    if (!negocio.estado?.abierto || !NegocioService.dentroDeHorario(negocio.horarios)) throw AppError.conflict('El negocio está cerrado en este momento', 'NEGOCIOCERRADO');
    if (negocio.estado?.aceptaPedidos === false) throw AppError.conflict('El negocio no está recibiendo pedidos ahora', 'NEGOCIONOACEPTA');

    // La dirección debe ser del propio cliente; se COPIA en el pedido
    const direccion = await Direccion.findOne({ where: { id: datos.direccionId, personaId: cliente.personaId }, transaction: t });
    if (!direccion) throw AppError.notFound('Dirección no encontrada', 'DIRECCIONNOENCONTRADA');
    if (negocio.local) {
      const km = distanciaKm({ lat: num(negocio.local.latitud), lng: num(negocio.local.longitud) }, { lat: num(direccion.latitud), lng: num(direccion.longitud) });
      if (km > num(negocio.radioKm)) {
        throw AppError.conflict(`Tu dirección está a ${km.toFixed(1)} km y este negocio entrega hasta ${num(negocio.radioKm)} km`, 'FUERADECOBERTURA', { distanciaKm: Number(km.toFixed(2)) });
      }
    }

    const productos = await Producto.findAll({ where: { id: items.map((i) => i.productoId), negocioId: negocio.id }, transaction: t });
    const porId = new Map(productos.map((p) => [String(p.id), p]));
    let subtotal = 0;
    for (const it of items) {
      const p = porId.get(it.productoId);
      if (!p) throw AppError.notFound('Uno de los productos ya no existe en este negocio', 'PRODUCTONOENCONTRADO', { productoId: Number(it.productoId) });
      if (p.estado !== ESTADOPRODUCTO.DISPONIBLE) throw AppError.conflict(`${p.nombre} no está disponible ahora`, 'PRODUCTONODISPONIBLE', { productoId: Number(p.id) });
      subtotal += centavos(p.precio) * it.cantidad;
    }
    if (subtotal < centavos(negocio.pedidoMinimo)) {
      throw AppError.badRequest(`El pedido mínimo de este negocio es $${num(negocio.pedidoMinimo).toFixed(2)}`, 'PEDIDOMINIMO', { pedidoMinimo: num(negocio.pedidoMinimo) });
    }
    for (const it of items) {
      const p = porId.get(it.productoId);
      if (p.controlaStock) await descontarStock(p, it.cantidad, t);
    }

    const envio = centavos(negocio.costoEnvio);
    const nuevo = await Pedido.create({
      clienteId: cliente.id,
      negocioId: negocio.id,
      metodoPago,
      direccionId: direccion.id,
      direccionEntrega: direccion.direccion,
      referenciaEntrega: direccion.referencia,
      latitud: direccion.latitud,
      longitud: direccion.longitud,
      subtotal: dinero(subtotal),
      costoEnvio: dinero(envio),
      total: dinero(subtotal + envio),
      notas: datos.notas?.trim() || null,
      tiempoEstimado: negocio.tiempoPreparacion + MINUTOSENTREGA,
    }, { transaction: t });
    await Detalle.bulkCreate(items.map((it, i) => {
      const p = porId.get(it.productoId);
      return { pedidoId: nuevo.id, linea: i + 1, productoId: p.id, nombre: p.nombre, precioUnitario: p.precio, cantidad: it.cantidad, subtotal: dinero(centavos(p.precio) * it.cantidad), notas: it.notas };
    }), { transaction: t });
    return { pedido: nuevo, negocio };
  }, { usuarioId: cliente.id });

  auditar({ usuarioId: cliente.id, accion: 'PEDIDOCREADO', entidad: 'PEDIDOS', entidadId: pedido.id, detalle: { total: num(pedido.total) }, req });
  await NotificacionService.notificar({
    io: req.io, usuarioId: negocio.duenoId, tipo: 'pedido_nuevo', titulo: '¡Nuevo pedido! 🛒',
    mensaje: `Pedido #${pedido.id} por $${num(pedido.total).toFixed(2)}`, pedidoId: pedido.id, datos: { estado: 'pendiente' },
  });
  avisarCambio(req.io, pedido, negocio.duenoId);
  return aApi(await cargar(pedido.id), req, { detalle: true });
}

// ---------------------------------------------------------------------------------------------
// Consultas
// ---------------------------------------------------------------------------------------------
const listarDelCliente = (clienteId, query, req) => listar({ clienteId, ...(filtroEstado(query.estado) && { estado: filtroEstado(query.estado) }) }, query, req, 'cliente');

async function listarDelNegocio(usuarioId, query, req) {
  const n = await NegocioService.exigirMio(usuarioId);
  return listar({ negocioId: n.id, ...(filtroEstado(query.estado) && { estado: filtroEstado(query.estado) }) }, query, req, 'vendedor');
}

// Rol de quien mira el pedido, o null si no tiene nada que ver con él
function rolEn(pedido, usuario) {
  if (pedido.clienteId === usuario.id) return 'cliente';
  if (pedido.negocio?.duenoId === usuario.id) return 'vendedor';
  if (pedido.repartidorId && pedido.repartidorId === usuario.id) return 'repartidor';
  if (usuario.tipoUsuario === 'administrador') return 'administrador';     // el administrador ve todos
  return null;
}

async function obtener(usuario, id, req) {
  const p = await cargar(id);
  let rol = p && rolEn(p, usuario);
  // Un repartidor aprobado puede ver un pedido libre (listo o por estar listo) para decidir si lo acepta
  if (p && !rol && usuario.tipoUsuario === 'repartidor' && !p.repartidorId && [E.CONFIRMADO, E.PREPARANDO, E.LISTO].includes(p.estado)) {
    const r = await Repartidor.findOne({ where: { usuarioId: usuario.id }, attributes: ['usuarioId', 'aprobacion'] });
    if (r?.aprobacion === APROBACION.APROBADO) rol = 'candidato';
  }
  if (!rol) throw noEncontrado();
  return aApi(p, req, { rol, detalle: true });
}

// Administrador: todos los pedidos, con filtro por estado ('activos', 'historial' o uno puntual) y por negocio
async function listarTodos(query, req) {
  const where = {};
  const estado = filtroEstado(query.estado) || APIAESTADOPEDIDO[query.estado];
  if (estado) where.estado = estado;
  if (query.negocioId) where.negocioId = query.negocioId;
  return listar(where, query, req, 'administrador');
}

// Administrador: cancela un pedido en curso (disputa). Devuelve el stock y avisa al cliente, al negocio y al
// repartidor (que queda libre para otra entrega).
async function cancelarComoAdmin(admin, id, { motivo }, req) {
  const pedido = await withTransaction(async (t) => {
    const p = await Pedido.findOne({ where: { id }, transaction: t, lock: t.LOCK.UPDATE });
    if (!p) throw noEncontrado();
    validarCancelacionAdmin(p.estado);
    await devolverStock(p.id, t);
    await p.update({ estado: E.CANCELADO, motivoCancelacion: `Cancelado por ValleXpress: ${motivo.trim()}` }, { transaction: t });
    return p;
  }, { usuarioId: admin.id });

  auditar({ usuarioId: admin.id, accion: 'PEDIDOCANCELADOADMIN', entidad: 'PEDIDOS', entidadId: id, detalle: { motivo }, req });
  const negocio = await Negocio.findOne({ where: { id: pedido.negocioId }, attributes: ['id', 'duenoId'] });
  const aviso = { io: req.io, tipo: 'pedido_cancelado', titulo: 'Pedido cancelado', pedidoId: pedido.id, datos: { estado: 'cancelado' } };
  await NotificacionService.notificar({ ...aviso, usuarioId: pedido.clienteId, mensaje: `ValleXpress canceló tu pedido #${pedido.id}: ${motivo.trim()}` });
  await NotificacionService.notificar({ ...aviso, usuarioId: negocio?.duenoId, mensaje: `ValleXpress canceló el pedido #${pedido.id}: ${motivo.trim()}` });
  if (pedido.repartidorId) await NotificacionService.notificar({ ...aviso, usuarioId: pedido.repartidorId, mensaje: `El pedido #${pedido.id} fue cancelado. Ya puedes tomar otro` });
  avisarCambio(req.io, pedido, negocio?.duenoId, { repartidores: true });
  return aApi(await cargar(id), req, { rol: 'administrador', detalle: true });
}

// ---------------------------------------------------------------------------------------------
// Negocio: confirmar, preparar, dejar listo o rechazar
// ---------------------------------------------------------------------------------------------
async function cambiarEstadoNegocio(usuario, id, { estado, motivo, tiempoEstimado }, req) {
  const siguiente = APIAESTADOPEDIDO[estado];
  const negocio = await NegocioService.exigirMio(usuario.id);
  const pedido = await withTransaction(async (t) => {
    const p = await Pedido.findOne({ where: { id, negocioId: negocio.id }, transaction: t, lock: t.LOCK.UPDATE });
    if (!p) throw noEncontrado();
    validarTransicion(p.estado, siguiente, 'vendedor');
    const cambios = { estado: siguiente };
    if (siguiente === E.RECHAZADO) {
      cambios.motivoCancelacion = motivo?.trim() || null;
      await devolverStock(p.id, t);
    }
    if (siguiente === E.CONFIRMADO && tiempoEstimado) cambios.tiempoEstimado = tiempoEstimado;
    await p.update(cambios, { transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: `PEDIDO${String(estado).toUpperCase()}`, entidad: 'PEDIDOS', entidadId: id, req });
  const [tipo, titulo, mensaje] = AVISOCLIENTE[siguiente];
  await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo, titulo, mensaje: mensaje(pedido, negocio.nombre), pedidoId: pedido.id, datos: { estado } });
  if (siguiente === E.LISTO) await avisarRepartidores(req.io, pedido, negocio.nombre);
  avisarCambio(req.io, pedido, negocio.duenoId, { repartidores: [E.CONFIRMADO, E.PREPARANDO, E.LISTO, E.RECHAZADO].includes(siguiente) });
  return aApi(await cargar(id), req, { rol: 'vendedor', detalle: true });
}

// ---------------------------------------------------------------------------------------------
// Repartidor: pedidos libres, aceptar, recoger y entregar
// ---------------------------------------------------------------------------------------------
// Libres: "listos" (se pueden aceptar ya) y "próximos" (el negocio los está preparando). Sin datos del cliente.
// Si el repartidor compartió su ubicación, cada pedido trae también a qué distancia está el negocio.
async function libresParaRepartidor(usuarioId, req) {
  const r = await RepartidorService.exigirPerfil(usuarioId);
  RepartidorService.exigirAprobado(r);
  const filas = await Pedido.findAll({
    where: { repartidorId: null, estado: { [Op.in]: [E.CONFIRMADO, E.PREPARANDO, E.LISTO] } },
    include: INCLUIR, order: [['fechaPedido', 'ASC'], [{ model: Detalle, as: 'detalles' }, 'linea', 'ASC']], limit: 100,
  });
  const yo = r.estado?.latitud != null ? { lat: num(r.estado.latitud), lng: num(r.estado.longitud) } : null;
  const pedidos = await aApi(filas, req, { rol: 'candidato' });
  for (const [i, p] of pedidos.entries()) {
    const local = filas[i].negocio?.local;
    p.distanciaAlNegocioKm = yo && local ? Number(distanciaKm(yo, { lat: num(local.latitud), lng: num(local.longitud) }).toFixed(2)) : null;
  }
  return { listos: pedidos.filter((p) => p.estado === 'listo'), proximos: pedidos.filter((p) => p.estado !== 'listo'), enLinea: r.estado?.disponible === true };
}

async function listarDelRepartidor(usuarioId, query, req) {
  await RepartidorService.exigirPerfil(usuarioId);
  const estado = query.estado === 'activos' ? { [Op.in]: [...ENCURSO, E.ENTREGADO] } : filtroEstado(query.estado);
  return listar({ repartidorId: usuarioId, ...(estado && { estado }) }, query, req, 'repartidor');
}

async function aceptar(usuario, id, req) {
  const r = await RepartidorService.exigirPerfil(usuario.id);
  RepartidorService.exigirAprobado(r);
  if (!r.estado?.disponible) throw AppError.conflict('Conéctate ("En línea") para aceptar pedidos', 'REPARTIDORDESCONECTADO');

  const pedido = await withTransaction(async (t) => {
    // Una entrega a la vez: así el cliente sabe que va directo hacia él
    if (await Pedido.count({ where: { repartidorId: usuario.id, estado: { [Op.in]: ENCURSO } }, transaction: t })) {
      throw AppError.conflict('Termina tu entrega en curso antes de aceptar otra', 'ENTREGAENCURSO');
    }
    const p = await Pedido.findOne({ where: { id }, transaction: t, lock: t.LOCK.UPDATE });   // si dos aceptan a la vez, gana uno
    if (!p) throw noEncontrado();
    if (p.repartidorId) throw AppError.conflict('Otro repartidor ya tomó este pedido', 'PEDIDOASIGNADO');
    if (p.estado !== E.LISTO) throw AppError.conflict('El negocio todavía no tiene listo este pedido', 'PEDIDONOLISTO');
    validarTransicion(p.estado, E.ENCAMINO, 'repartidor');
    await p.update({ estado: E.ENCAMINO, repartidorId: usuario.id }, { transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDOACEPTADO', entidad: 'PEDIDOS', entidadId: id, req });
  await avisarPasoRepartidor(req, pedido, usuario, { repartidores: true });
  return aApi(await cargar(id), req, { rol: 'repartidor', detalle: true });
}

// Recoger (EN CAMINO -> RECOGIDO) o entregar (RECOGIDO -> ENTREGADO): solo el repartidor asignado
async function pasoRepartidor(usuario, id, siguiente, req) {
  const pedido = await withTransaction(async (t) => {
    const p = await Pedido.findOne({ where: { id, repartidorId: usuario.id }, transaction: t, lock: t.LOCK.UPDATE });
    if (!p) throw noEncontrado();
    validarTransicion(p.estado, siguiente, 'repartidor');
    await p.update({ estado: siguiente }, { transaction: t });
    if (siguiente === E.ENTREGADO) await RepartidorEstado.increment('numeroEntregas', { by: 1, where: { usuarioId: usuario.id }, transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: siguiente === E.RECOGIDO ? 'PEDIDORECOGIDO' : 'PEDIDOENTREGADO', entidad: 'PEDIDOS', entidadId: id, req });
  await avisarPasoRepartidor(req, pedido, usuario);
  return aApi(await cargar(id), req, { rol: 'repartidor', detalle: true });
}

// Avisos de un paso del repartidor: al cliente siempre; al negocio cuando le asignan repartidor y cuando lo recoge
async function avisarPasoRepartidor(req, pedido, repartidor, opciones = {}) {
  const negocio = await Negocio.findOne({ where: { id: pedido.negocioId }, attributes: ['id', 'nombre', 'duenoId'] });
  const [tipo, titulo, mensaje] = AVISOCLIENTE[pedido.estado];
  await NotificacionService.notificar({ io: req.io, usuarioId: pedido.clienteId, tipo, titulo, mensaje: mensaje(pedido, negocio.nombre, repartidor.nombre), pedidoId: pedido.id, datos: { estado: ESTADOPEDIDOAAPI[pedido.estado] } });
  const alNegocio = {
    [E.ENCAMINO]: ['repartidor_asignado', 'Repartidor en camino 🛵', `${repartidor.nombre} va por el pedido #${pedido.id}`],
    [E.RECOGIDO]: ['pedido_recogido', 'Pedido recogido ✅', `${repartidor.nombre} recogió el pedido #${pedido.id}`],
  }[pedido.estado];
  if (alNegocio) {
    await NotificacionService.notificar({ io: req.io, usuarioId: negocio.duenoId, tipo: alNegocio[0], titulo: alNegocio[1], mensaje: alNegocio[2], pedidoId: pedido.id, datos: { estado: ESTADOPEDIDOAAPI[pedido.estado] } });
  }
  avisarCambio(req.io, pedido, negocio.duenoId, opciones);
}

// ---------------------------------------------------------------------------------------------
// Cliente: cancelar (solo pendiente), confirmar que lo recibió y calificar
// ---------------------------------------------------------------------------------------------
async function cancelar(usuario, id, { motivo } = {}, req) {
  const pedido = await withTransaction(async (t) => {
    const p = await Pedido.findOne({ where: { id, clienteId: usuario.id }, transaction: t, lock: t.LOCK.UPDATE });
    if (!p) throw noEncontrado();
    if (p.estado !== E.PENDIENTE) throw AppError.conflict('El negocio ya aceptó tu pedido; ya no se puede cancelar desde la app', 'PEDIDOENPROCESO');
    validarTransicion(p.estado, E.CANCELADO, 'cliente');
    await devolverStock(p.id, t);
    await p.update({ estado: E.CANCELADO, motivoCancelacion: motivo?.trim() || null }, { transaction: t });
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDOCANCELADO', entidad: 'PEDIDOS', entidadId: id, req });
  const negocio = await Negocio.findOne({ where: { id: pedido.negocioId }, attributes: ['id', 'duenoId'] });
  await NotificacionService.notificar({
    io: req.io, usuarioId: negocio?.duenoId, tipo: 'pedido_cancelado', titulo: 'Pedido cancelado',
    mensaje: `El cliente canceló el pedido #${pedido.id}`, pedidoId: pedido.id, datos: { estado: 'cancelado' },
  });
  avisarCambio(req.io, pedido, negocio?.duenoId);
  return aApi(await cargar(id), req, { detalle: true });
}

async function marcarRecibido(usuario, id, req) {
  const pedido = await withTransaction(async (t) => {
    const p = await Pedido.findOne({ where: { id, clienteId: usuario.id }, transaction: t, lock: t.LOCK.UPDATE });
    if (!p) throw noEncontrado();
    validarTransicion(p.estado, E.RECIBIDO, 'cliente');
    await p.update({ estado: E.RECIBIDO, pagado: true }, { transaction: t });

    // Contadores: pedidos del negocio y unidades vendidas de cada producto
    await NegocioEstado.increment('numeroPedidos', { by: 1, where: { negocioId: p.negocioId }, transaction: t });
    const detalles = await Detalle.findAll({ where: { pedidoId: p.id }, transaction: t });
    for (const d of detalles) {
      await sequelize.query('UPDATE tproductosinventario SET numerovendidos = numerovendidos + :n WHERE cproducto = :id', { replacements: { n: d.cantidad, id: d.productoId }, transaction: t });
    }
    return p;
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDORECIBIDO', entidad: 'PEDIDOS', entidadId: id, req });
  const negocio = await Negocio.findOne({ where: { id: pedido.negocioId }, attributes: ['id', 'duenoId'] });
  const aviso = { tipo: 'pedido_recibido', titulo: 'Pedido completado ✅', mensaje: `El cliente confirmó que recibió el pedido #${pedido.id}`, pedidoId: pedido.id, datos: { estado: 'recibido' } };
  await NotificacionService.notificar({ io: req.io, usuarioId: negocio?.duenoId, ...aviso });
  if (pedido.repartidorId) await NotificacionService.notificar({ io: req.io, usuarioId: pedido.repartidorId, ...aviso });
  avisarCambio(req.io, pedido, negocio?.duenoId);
  return aApi(await cargar(id), req, { detalle: true });
}

// Recalcula el promedio y el número de calificaciones del negocio
async function recalcularNegocio(negocioId, t) {
  await sequelize.query(
    `UPDATE tnegociosestado SET
       calificacion = COALESCE((SELECT ROUND(AVG(puntuacion), 2) FROM tcalificaciones WHERE cnegocio = :id AND destino = 'NEGOCIO'), 0),
       numerocalificaciones = (SELECT COUNT(*) FROM tcalificaciones WHERE cnegocio = :id AND destino = 'NEGOCIO')
     WHERE cnegocio = :id`,
    { replacements: { id: negocioId }, transaction: t },
  );
}

// Recalcula el promedio y el número de calificaciones del repartidor
async function recalcularRepartidor(usuarioId, t) {
  await sequelize.query(
    `UPDATE trepartidoresestado SET
       calificacion = COALESCE((SELECT ROUND(AVG(puntuacion), 2) FROM tcalificaciones WHERE cusuario_repartidor = :id AND destino = 'REPARTIDOR'), 0),
       numerocalificaciones = (SELECT COUNT(*) FROM tcalificaciones WHERE cusuario_repartidor = :id AND destino = 'REPARTIDOR')
     WHERE cusuario = :id`,
    { replacements: { id: usuarioId }, transaction: t },
  );
}

async function calificar(usuario, id, { puntuacion, comentario, destino = 'negocio' }, req) {
  const p = await Pedido.findOne({ where: { id, clienteId: usuario.id } });
  if (!p) throw noEncontrado();
  if (![E.ENTREGADO, E.RECIBIDO].includes(p.estado)) throw AppError.conflict('Podrás calificar cuando recibas tu pedido', 'PEDIDONOENTREGADO');
  const DESTINO = String(destino).toUpperCase();
  if (DESTINO === 'REPARTIDOR' && !p.repartidorId) throw AppError.badRequest('Este pedido no tuvo repartidor', 'SINREPARTIDOR');
  if (await Calificacion.findOne({ where: { pedidoId: id, destino: DESTINO } })) throw AppError.conflict('Ya calificaste este pedido', 'YACALIFICADO');

  await withTransaction(async (t) => {
    await Calificacion.create({
      pedidoId: p.id, destino: DESTINO, autorId: usuario.id, puntuacion, comentario: comentario?.trim() || null,
      negocioId: DESTINO === 'NEGOCIO' ? p.negocioId : null, repartidorId: DESTINO === 'REPARTIDOR' ? p.repartidorId : null,
    }, { transaction: t });
    if (DESTINO === 'NEGOCIO') await recalcularNegocio(p.negocioId, t);
    else await recalcularRepartidor(p.repartidorId, t);
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'PEDIDOCALIFICADO', entidad: 'CALIFICACIONES', entidadId: id, detalle: { destino: DESTINO, puntuacion }, req });
  return aApi(await cargar(id), req, { detalle: true });
}

// Métodos de pago que la app puede ofrecer hoy
async function metodosPago() {
  const filas = await sequelize.query(
    "SELECT cmetodopago AS codigo, descripcion FROM tmetodospago WHERE esactivo AND cidioma = 'es' AND fhasta = '2999-12-31 00:00:00-05' ORDER BY cmetodopago",
    { type: QueryTypes.SELECT },
  );
  return filas.map((f) => ({ codigo: METODOPAGOAAPI[f.codigo], descripcion: f.descripcion }));
}

module.exports = {
  crear, listarDelCliente, listarDelNegocio, obtener, cambiarEstadoNegocio, cancelar, marcarRecibido, calificar, metodosPago,
  libresParaRepartidor, listarDelRepartidor, aceptar,
  recoger: (usuario, id, req) => pasoRepartidor(usuario, id, E.RECOGIDO, req),
  entregar: (usuario, id, req) => pasoRepartidor(usuario, id, E.ENTREGADO, req),
  listarTodos, cancelarComoAdmin,
  aApi, cargar, distanciaKm,
};
