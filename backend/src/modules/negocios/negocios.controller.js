const asyncHandler = require('../../shared/helpers/asyncHandler');
const NegocioService = require('./negocio.service');
const ProductoService = require('../productos/producto.service');

// Controllers delgados: la lógica está en negocio.service.js y producto.service.js; las validaciones, en los *.schema.js.

// --- Público (cualquier usuario autenticado) ---
const categorias = asyncHandler(async (req, res) => res.json({ categorias: await NegocioService.categorias() }));
const listar = asyncHandler(async (req, res) => res.json(await NegocioService.listar(req.query, req)));
const obtener = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.obtener(Number(req.params.id), req.usuario, req) }));
const menu = asyncHandler(async (req, res) => res.json(await ProductoService.menu(Number(req.params.id), req.usuario, req)));

// --- Mi negocio (vendedor) ---
// El dueño es quien inicia sesión; cuando el administrador gestiona un negocio, req.duenoId trae al dueño
// (lo fija admin.routes después de verificar el rol).
const u = (req) => req.duenoId || req.usuario.id;
const miNegocio = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.miNegocio(u(req), req) }));
const crear = asyncHandler(async (req, res) => res.status(201).json({ negocio: await NegocioService.crear(u(req), req.body, req) }));
const actualizar = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.actualizar(u(req), req.body, req) }));
// Solo el dueño (no el administrador que gestiona) pide una nueva revisión
const revision = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.pedirRevision(req.usuario.id, req) }));
const local = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.fijarLocal(u(req), req.body, req) }));
const horarios = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.fijarHorarios(u(req), req.body.horarios, req) }));
const estado = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.cambiarEstado(u(req), req.body, req) }));
const logo = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.subirImagen(u(req), 'logo', req.body.imagen, req) }));
const portada = asyncHandler(async (req, res) => res.json({ negocio: await NegocioService.subirImagen(u(req), 'portada', req.body.imagen, req) }));

// --- Productos de mi negocio ---
const pid = (req) => Number(req.params.id);
const misProductos = asyncHandler(async (req, res) => res.json(await ProductoService.listarMios(u(req), req)));
const crearProducto = asyncHandler(async (req, res) => res.status(201).json({ producto: await ProductoService.crear(u(req), req.body, req) }));
const actualizarProducto = asyncHandler(async (req, res) => res.json({ producto: await ProductoService.actualizar(u(req), pid(req), req.body, req) }));
const estadoProducto = asyncHandler(async (req, res) => res.json({ producto: await ProductoService.cambiarEstado(u(req), pid(req), req.body.estado, req) }));
const stockProducto = asyncHandler(async (req, res) => res.json({ producto: await ProductoService.fijarStock(u(req), pid(req), req.body.stock, req) }));
const imagenProducto = asyncHandler(async (req, res) => res.json({ producto: await ProductoService.subirImagen(u(req), pid(req), req.body.imagen, req) }));
const eliminarProducto = asyncHandler(async (req, res) => {
  await ProductoService.eliminar(u(req), pid(req), req);
  res.json({ message: 'Producto eliminado' });
});

module.exports = {
  categorias, listar, obtener, menu,
  revision,
  miNegocio, crear, actualizar, local, horarios, estado, logo, portada,
  misProductos, crearProducto, actualizarProducto, estadoProducto, stockProducto, imagenProducto, eliminarProducto,
};
