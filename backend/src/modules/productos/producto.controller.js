const asyncHandler = require('../../shared/helpers/asyncHandler');
const productoService = require('./producto.service');

// Controller delgado: recibe la petición, llama al servicio y responde. La lógica está en producto.service.js
// y las validaciones en producto.schema.js. Las respuestas conservan el formato que ya consume la app.

const crear = asyncHandler(async (req, res) => {
  const resultado = await productoService.crear(req.usuario.id, req.body, req);
  res.status(201).json({ message: 'Producto creado exitosamente', ...resultado });
});

const listar = asyncHandler(async (req, res) => res.json(await productoService.listar(req.query, req)));

const listarPorVendedor = asyncHandler(async (req, res) =>
  res.json(await productoService.listarPorVendedor(req.params.vendedorId, req)));

const misProductos = asyncHandler(async (req, res) => res.json(await productoService.misProductos(req.usuario.id, req)));

const obtenerPorId = asyncHandler(async (req, res) => res.json(await productoService.obtener(req.params.id, req)));

const actualizar = asyncHandler(async (req, res) => {
  const resultado = await productoService.actualizar(req.usuario.id, req.params.id, req.body, req);
  res.json({ message: 'Producto actualizado exitosamente', ...resultado });
});

const eliminar = asyncHandler(async (req, res) => {
  await productoService.eliminar(req.usuario.id, req.params.id, req);
  res.json({ message: 'Producto eliminado exitosamente' });
});

const cambiarDisponible = asyncHandler(async (req, res) => {
  const resultado = await productoService.cambiarDisponible(req.usuario.id, req.params.id, req.body.disponible, req);
  res.json({ message: 'Disponibilidad actualizada', ...resultado });
});

module.exports = { crear, listar, listarPorVendedor, misProductos, obtenerPorId, actualizar, eliminar, cambiarDisponible };
