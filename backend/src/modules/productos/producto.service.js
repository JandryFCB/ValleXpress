const { Op } = require('sequelize');
const { Producto, Inventario } = require('./producto.model');
const { Negocio } = require('../negocios/negocio.model');
const NegocioService = require('../negocios/negocio.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const { auditar } = require('../../shared/services/log.service');
const { APROBACION, ESTADOPRODUCTO: E, ESTADOPRODUCTOAAPI, APIAESTADOPRODUCTO } = require('../../shared/constants/codigos');

// Lógica de los PRODUCTOS de un negocio. El cliente ve los disponibles y agotados (los ocultos no) de negocios
// aprobados. El dueño ve y edita todos los suyos. Cada cambio (por ejemplo de precio) queda en el historial.
//   * Si el producto controla stock: al llegar a 0 pasa solo a "agotado" y al reponer vuelve a "disponible".

const MAXPRODUCTOS = 300;
const num = (v) => (v === null || v === undefined ? null : Number(v));
const noEncontrado = () => AppError.notFound('Producto no encontrado', 'PRODUCTONOENCONTRADO');
const ORDEN = [['seccion', 'ASC NULLS LAST'], ['orden', 'ASC'], ['nombre', 'ASC']];

async function aApi(entrada, req, { privado = false } = {}) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  const urls = await ArchivoService.mapaUrls(req, lista.map((p) => p.imagenId));
  const salida = lista.map((p) => {
    const inv = p.inventario || {};
    const imagen = urls[String(p.imagenId)];
    return {
      id: Number(p.id),
      negocioId: Number(p.negocioId),
      nombre: p.nombre,
      descripcion: p.descripcion,
      precio: num(p.precio),
      estado: ESTADOPRODUCTOAAPI[p.estado],
      disponible: p.estado === E.DISPONIBLE && (!p.controlaStock || (inv.stock ?? 0) > 0),
      seccion: p.seccion,
      imagen: imagen?.url || null,
      miniatura: imagen?.miniatura || null,
      orden: p.orden,
      controlaStock: p.controlaStock,
      ...(privado && { stock: inv.stock ?? 0, vendidos: inv.vendidos ?? 0 }),
    };
  });
  return Array.isArray(entrada) ? salida : salida[0];
}

// Secciones del menú en el orden en que aparecen los productos ("Sin sección" al final)
const seccionesDe = (productos) => [...new Set(productos.map((p) => p.seccion || null))];

// ---------------------------------------------------------------------------------------------
// Público: el menú de un negocio
// ---------------------------------------------------------------------------------------------
async function menu(negocioId, usuario, req) {
  const n = await Negocio.findOne({ where: { id: negocioId }, attributes: ['id', 'duenoId', 'aprobacion'] });
  if (!n || (n.aprobacion !== APROBACION.APROBADO && n.duenoId !== usuario.id)) {
    throw AppError.notFound('Negocio no encontrado', 'NEGOCIONOENCONTRADO');
  }
  const filas = await Producto.findAll({
    where: { negocioId, estado: { [Op.ne]: E.OCULTO } },
    include: [{ model: Inventario, as: 'inventario' }],
    order: ORDEN,
  });
  const productos = await aApi(filas, req);
  return { productos, secciones: seccionesDe(productos) };
}

// ---------------------------------------------------------------------------------------------
// Dueño (vendedor)
// ---------------------------------------------------------------------------------------------
async function propio(usuarioId, id, opciones = {}) {
  const n = await NegocioService.exigirMio(usuarioId, opciones);
  const p = await Producto.findOne({ where: { id, negocioId: n.id }, include: [{ model: Inventario, as: 'inventario' }], ...opciones });
  if (!p) throw noEncontrado();                         // ajeno o inexistente: mismo error
  return p;
}

const recargar = (id) => Producto.findOne({ where: { id }, include: [{ model: Inventario, as: 'inventario' }] });

async function listarMios(usuarioId, req) {
  const n = await NegocioService.exigirMio(usuarioId);
  const filas = await Producto.findAll({ where: { negocioId: n.id }, include: [{ model: Inventario, as: 'inventario' }], order: ORDEN });
  const productos = await aApi(filas, req, { privado: true });
  return { productos, secciones: seccionesDe(productos) };
}

// Estado que corresponde según el stock (solo si controla stock y no está oculto)
function estadoSegunStock(estado, controlaStock, stock) {
  if (!controlaStock || estado === E.OCULTO) return estado;
  if (stock <= 0 && estado === E.DISPONIBLE) return E.AGOTADO;
  if (stock > 0 && estado === E.AGOTADO) return E.DISPONIBLE;
  return estado;
}

const texto = (v) => (typeof v === 'string' ? v.trim() || null : v ?? null);

async function crear(usuarioId, datos, req) {
  const n = await NegocioService.exigirMio(usuarioId);
  if (await Producto.count({ where: { negocioId: n.id } }) >= MAXPRODUCTOS) {
    throw AppError.conflict(`Puedes tener hasta ${MAXPRODUCTOS} productos`, 'LIMITEPRODUCTOS');
  }
  const controlaStock = datos.controlaStock === true;
  const stock = controlaStock ? Number(datos.stock || 0) : 0;
  const nuevo = await withTransaction(async (t) => {
    const imagen = datos.imagen
      ? await ArchivoService.guardarBase64({ base64: datos.imagen, categoria: 'PRODUCTO', propietario: usuarioId }, { transaction: t })
      : null;
    const p = await Producto.create({
      negocioId: n.id,
      nombre: datos.nombre.trim(),
      descripcion: texto(datos.descripcion),
      precio: datos.precio,
      seccion: texto(datos.seccion),
      orden: datos.orden ?? 0,
      controlaStock,
      imagenId: imagen?.id ?? null,
      estado: estadoSegunStock(APIAESTADOPRODUCTO[datos.estado] || E.DISPONIBLE, controlaStock, stock),
    }, { transaction: t });
    if (controlaStock) await Inventario.update({ stock, ultimoMovimiento: new Date() }, { where: { productoId: p.id }, transaction: t });
    return p;
  }, { usuarioId });
  auditar({ usuarioId, accion: 'PRODUCTOCREADO', entidad: 'PRODUCTOS', entidadId: nuevo.id, req });
  return aApi(await recargar(nuevo.id), req, { privado: true });
}

async function actualizar(usuarioId, id, datos, req) {
  const p = await propio(usuarioId, id);
  const cambios = {};
  for (const campo of ['nombre', 'descripcion', 'seccion']) if (datos[campo] !== undefined) cambios[campo] = texto(datos[campo]);
  for (const campo of ['precio', 'orden']) if (datos[campo] !== undefined) cambios[campo] = datos[campo];
  if (cambios.nombre === null) throw AppError.badRequest('El nombre es requerido', 'NOMBREREQUERIDO');
  if (datos.controlaStock !== undefined) cambios.controlaStock = datos.controlaStock === true;
  if (datos.estado !== undefined) cambios.estado = APIAESTADOPRODUCTO[datos.estado];
  const stock = p.inventario?.stock ?? 0;
  const estadoFinal = estadoSegunStock(cambios.estado ?? p.estado, cambios.controlaStock ?? p.controlaStock, stock);
  if (estadoFinal !== p.estado) cambios.estado = estadoFinal;

  const precioAntes = Number(p.precio);
  await withTransaction((t) => p.update(cambios, { transaction: t }), { usuarioId });
  if (datos.precio !== undefined && Number(datos.precio) !== precioAntes) {
    auditar({ usuarioId, accion: 'PRODUCTOPRECIO', entidad: 'PRODUCTOS', entidadId: id, detalle: { precio: datos.precio }, req });
  }
  return aApi(await recargar(id), req, { privado: true });
}

async function cambiarEstado(usuarioId, id, estadoApi, req) {
  const p = await propio(usuarioId, id);
  const pedido = APIAESTADOPRODUCTO[estadoApi];
  // No se puede marcar "disponible" un producto que controla stock y no tiene unidades
  if (pedido === E.DISPONIBLE && p.controlaStock && (p.inventario?.stock ?? 0) <= 0) {
    throw AppError.conflict('No tiene stock: agrega unidades para marcarlo como disponible', 'SINSTOCK');
  }
  await withTransaction((t) => p.update({ estado: pedido }, { transaction: t }), { usuarioId });
  return aApi(await recargar(id), req, { privado: true });
}

async function fijarStock(usuarioId, id, stock, req) {
  const p = await propio(usuarioId, id);
  if (!p.controlaStock) throw AppError.conflict('Este producto no controla stock. Actívalo primero.', 'SINCONTROLSTOCK');
  await withTransaction(async (t) => {
    await Inventario.update({ stock, ultimoMovimiento: new Date() }, { where: { productoId: p.id }, transaction: t });
    const estado = estadoSegunStock(p.estado, true, stock);
    if (estado !== p.estado) await p.update({ estado }, { transaction: t });
  }, { usuarioId });
  return aApi(await recargar(id), req, { privado: true });
}

async function subirImagen(usuarioId, id, base64, req) {
  const p = await propio(usuarioId, id);
  await withTransaction(async (t) => {
    const archivo = await ArchivoService.guardarBase64({ base64, categoria: 'PRODUCTO', propietario: usuarioId }, { transaction: t });
    await p.update({ imagenId: archivo.id }, { transaction: t });
  }, { usuarioId });
  return aApi(await recargar(id), req, { privado: true });
}

// Se borra la fila vigente; el trigger deja la copia cerrada en el historial (los pedidos viejos lo siguen viendo)
async function eliminar(usuarioId, id, req) {
  const p = await propio(usuarioId, id);
  await withTransaction((t) => p.destroy({ transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'PRODUCTOELIMINADO', entidad: 'PRODUCTOS', entidadId: id, req });
}

module.exports = { menu, listarMios, crear, actualizar, cambiarEstado, fijarStock, subirImagen, eliminar, aApi };
