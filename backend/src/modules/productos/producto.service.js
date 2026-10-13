const Producto = require('./producto.model');
const Vendedor = require('../vendedores/vendedor.model');
const { VISIBLE } = require('../vendedores/vendedor.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const CatalogoService = require('../../shared/services/catalogo.service');
const { auditar } = require('../../shared/services/log.service');
const { ESTADOPRODUCTO, APROBACION } = require('../../shared/constants/codigos');

// Lógica de negocio de los productos. El controller solo llama a estos métodos.

const VENDEDORINCLUIDO = (extra = {}) => ({
  model: Vendedor,
  as: 'vendedor',
  attributes: ['id', 'nombreNegocio', 'categoria', 'datosExtra', 'calificacionPromedio'],
  ...extra,
});
const num = (v) => (v === null || v === undefined ? null : Number(v));

// Convierte productos al formato que consume la app
async function aApi(entrada, req) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  const urls = await ArchivoService.mapaUrls(req, lista.map((p) => p.imagenId));
  const salida = await Promise.all(lista.map(async (p) => ({
    id: p.id,
    vendedorId: p.vendedorId,
    nombre: p.nombre,
    descripcion: p.descripcion,
    precio: num(p.precio),
    imagen: urls[p.imagenId]?.url || null,
    imagenMiniatura: urls[p.imagenId]?.miniatura || null,
    categoria: await CatalogoService.categoriaTexto(p),
    categoriaCodigo: p.categoria,
    disponible: p.disponible,
    estado: p.estado,
    tiempoPreparacion: p.tiempoPreparacion,
    stock: p.stock,
    controlaStock: p.controlaStock,
    createdAt: p.creadoEn,
    ...(p.vendedor && {
      vendedor: {
        id: p.vendedor.id,
        nombreNegocio: p.vendedor.nombreNegocio,
        categoria: await CatalogoService.categoriaTexto(p.vendedor),
        calificacionPromedio: num(p.vendedor.calificacionPromedio),
      },
    }),
  })));
  return Array.isArray(entrada) ? salida : salida[0];
}

async function vendedorDe(usuarioId, mensaje = 'Vendedor no encontrado') {
  const vendedor = await Vendedor.findOne({ where: { id: usuarioId } });
  if (!vendedor) throw AppError.notFound(mensaje, 'VENDEDORNOENCONTRADO');
  return vendedor;
}

async function productoDelVendedor(usuarioId, id) {
  const vendedor = await vendedorDe(usuarioId);
  const producto = await Producto.findOne({ where: { id, vendedorId: vendedor.id } });
  if (!producto) throw AppError.notFound('Producto no encontrado o no te pertenece', 'PRODUCTONOENCONTRADO');
  return producto;
}

// undefined = sin cambios · null o '' = quitar la imagen · URL = sin cambios · cualquier otro texto = imagen en base64
async function resolverImagen(valor, usuarioId) {
  if (valor === undefined) return undefined;
  if (valor === null || valor === '') return null;
  if (/^https?:\/\//i.test(valor)) return undefined;
  return (await ArchivoService.guardarBase64({ base64: valor, categoria: 'PRODUCTO', propietario: usuarioId })).id;
}

// Con control de stock: sin unidades -> AGOTADO; al volver a tener unidades -> DISPONIBLE
function estadoSegunStock(estado, stock, controlaStock) {
  if (!controlaStock) return estado;
  if (stock === 0 && estado === ESTADOPRODUCTO.DISPONIBLE) return ESTADOPRODUCTO.AGOTADO;
  if (stock > 0 && estado === ESTADOPRODUCTO.AGOTADO) return ESTADOPRODUCTO.DISPONIBLE;
  return estado;
}

async function crear(usuarioId, datos, req) {
  const vendedor = await vendedorDe(usuarioId, 'Debes registrar tu negocio primero');
  if (vendedor.aprobacion !== APROBACION.APROBADO) throw AppError.forbidden('Tu negocio aún no está aprobado', 'NEGOCIONOAPROBADO');

  const imagenId = await resolverImagen(datos.imagen, usuarioId);
  const controlaStock = datos.stock !== undefined;                 // sin stock informado: no se controla (siempre disponible)
  const stock = controlaStock ? Number(datos.stock) : 0;
  const disponible = datos.disponible === undefined ? true : datos.disponible === true || datos.disponible === 'true';
  const estado = estadoSegunStock(disponible ? ESTADOPRODUCTO.DISPONIBLE : ESTADOPRODUCTO.NODISPONIBLE, stock, controlaStock);

  const producto = await withTransaction((t) => Producto.create({
    vendedorId: vendedor.id,
    nombre: datos.nombre.trim(),
    descripcion: datos.descripcion,
    precio: Number(datos.precio),
    imagenId: imagenId || null,
    ...CatalogoService.categoriaParaGuardar(datos.categoria),
    estado,
    controlaStock,
    stock,
    tiempoPreparacion: datos.tiempoPreparacion ? Number(datos.tiempoPreparacion) : null,
    creadoPor: usuarioId,
  }, { transaction: t }), { usuarioId });

  auditar({ usuarioId, accion: 'PRODUCTOCREADO', entidad: 'PRODUCTOS', entidadId: producto.id, req });
  return { producto: await aApi(producto, req) };
}

// Público: solo productos de vendedores aprobados y activos. Paginado para no devolver listas enormes.
async function listar({ limite = 200, pagina = 1 }, req) {
  const tope = Math.min(Number(limite) || 200, 500);
  const salto = (Math.max(Number(pagina) || 1, 1) - 1) * tope;
  const { rows, count } = await Producto.findAndCountAll({
    where: { activo: true },
    include: [VENDEDORINCLUIDO({ required: true, where: VISIBLE })],
    order: [['creadoEn', 'DESC']],
    limit: tope,
    offset: salto,
  });
  return { productos: await aApi(rows, req), total: count, pagina: Math.floor(salto / tope) + 1, limite: tope };
}

async function listarPorVendedor(vendedorId, req) {
  const vendedor = await Vendedor.findOne({ where: { id: vendedorId, ...VISIBLE } });
  if (!vendedor) throw AppError.notFound('Vendedor no encontrado', 'VENDEDORNOENCONTRADO');
  const productos = await Producto.findAll({ where: { vendedorId, activo: true }, order: [['creadoEn', 'DESC']] });
  return { productos: await aApi(productos, req) };
}

async function misProductos(usuarioId, req) {
  const vendedor = await vendedorDe(usuarioId, 'No tienes un negocio registrado');
  const productos = await Producto.findAll({ where: { vendedorId: vendedor.id }, order: [['creadoEn', 'DESC']] });
  return { productos: await aApi(productos, req) };
}

async function obtener(id, req) {
  const producto = await Producto.findOne({ where: { id }, include: [VENDEDORINCLUIDO({ required: true, where: VISIBLE })] });
  if (!producto) throw AppError.notFound('Producto no encontrado', 'PRODUCTONOENCONTRADO');
  return { producto: await aApi(producto, req) };
}

async function actualizar(usuarioId, id, datos, req) {
  const producto = await productoDelVendedor(usuarioId, id);
  const imagenId = await resolverImagen(datos.imagen, usuarioId);

  const cambios = { actualizadoPor: usuarioId };
  if (datos.nombre !== undefined) cambios.nombre = datos.nombre.trim();
  if (datos.descripcion !== undefined) cambios.descripcion = datos.descripcion;
  if (datos.precio !== undefined) cambios.precio = Number(datos.precio);
  if (imagenId !== undefined) cambios.imagenId = imagenId;
  if (datos.categoria !== undefined) Object.assign(cambios, CatalogoService.categoriaParaGuardar(datos.categoria));
  if (datos.tiempoPreparacion !== undefined) cambios.tiempoPreparacion = Number(datos.tiempoPreparacion);

  let estado = producto.estado;
  if (datos.disponible !== undefined) {
    estado = datos.disponible === true || datos.disponible === 'true' ? ESTADOPRODUCTO.DISPONIBLE : ESTADOPRODUCTO.NODISPONIBLE;
  }
  if (datos.stock !== undefined) {
    cambios.stock = Number(datos.stock);
    cambios.controlaStock = true;
    estado = estadoSegunStock(estado, cambios.stock, true);
  }
  cambios.estado = estado;

  await withTransaction((t) => producto.update(cambios, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'PRODUCTOACTUALIZADO', entidad: 'PRODUCTOS', entidadId: id, req });
  return { producto: await aApi(producto, req) };
}

async function eliminar(usuarioId, id, req) {
  const producto = await productoDelVendedor(usuarioId, id);
  await withTransaction((t) => producto.destroy({ transaction: t }), { usuarioId });        // borrado lógico (ELIMINADOEN)
  auditar({ usuarioId, accion: 'PRODUCTOELIMINADO', entidad: 'PRODUCTOS', entidadId: id, req });
}

async function cambiarDisponible(usuarioId, id, disponible, req) {
  const producto = await productoDelVendedor(usuarioId, id);
  await withTransaction((t) => producto.update({
    estado: disponible ? ESTADOPRODUCTO.DISPONIBLE : ESTADOPRODUCTO.NODISPONIBLE, actualizadoPor: usuarioId,
  }, { transaction: t }), { usuarioId });
  return { producto: await aApi(producto, req) };
}

module.exports = { crear, listar, listarPorVendedor, misProductos, obtener, actualizar, eliminar, cambiarDisponible };
