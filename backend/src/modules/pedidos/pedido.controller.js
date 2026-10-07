const asyncHandler = require('../../shared/helpers/asyncHandler');
const pedidoService = require('./pedido.service');

// Controller delgado: la lógica está en pedido.service.js, el flujo de estados en pedido_estado.service.js y las
// validaciones en pedido.schema.js. Las respuestas conservan el formato que ya consume la app.

const crear = asyncHandler(async (req, res) => res.status(201).json(await pedidoService.crear(req.usuario, req.body, req)));

const misPedidos = asyncHandler(async (req, res) => res.json(await pedidoService.listarDelCliente(req.usuario.id, req.query, req)));

const pedidosVendedor = asyncHandler(async (req, res) => res.json(await pedidoService.listarDelVendedor(req.usuario.id, req.query, req)));

const obtenerPorId = asyncHandler(async (req, res) => res.json(await pedidoService.obtener(req.usuario, req.params.id, req)));

const actualizarEstado = asyncHandler(async (req, res) =>
  res.json(await pedidoService.cambiarEstadoVendedor(req.usuario, req.params.id, req.body, req)));

const cancelar = asyncHandler(async (req, res) => {
  await pedidoService.cancelar(req.usuario, req.params.id, req.body, req);
  res.json({ message: 'Pedido cancelado exitosamente' });
});

const aceptarRepartidor = asyncHandler(async (req, res) =>
  res.json(await pedidoService.aceptarRepartidor(req.usuario, req.params.id, req.body.costoDelivery, req)));

const marcarEnCamino = asyncHandler(async (req, res) => {
  await pedidoService.marcarEnCamino(req.usuario, req.params.id);
  res.json({ message: 'Pedido marcado como en camino' });
});

const marcarRecogido = asyncHandler(async (req, res) => {
  const pedido = await pedidoService.marcarRecogido(req.usuario, req.params.id, req);
  res.json({ message: 'Pedido marcado como recogido', pedido });
});

const marcarEntregado = asyncHandler(async (req, res) => {
  await pedidoService.marcarEntregado(req.usuario, req.params.id, req);
  res.json({ message: 'Pedido marcado como entregado' });
});

const marcarRecibidoCliente = asyncHandler(async (req, res) =>
  res.json(await pedidoService.marcarRecibido(req.usuario, req.params.id, req)));

const calificar = asyncHandler(async (req, res) => {
  await pedidoService.calificar(req.usuario, req.params.id, req.body, req);
  res.json({ message: 'Calificación registrada' });
});

module.exports = {
  crear, misPedidos, pedidosVendedor, obtenerPorId, actualizarEstado, cancelar, aceptarRepartidor,
  marcarEnCamino, marcarRecogido, marcarEntregado, marcarRecibidoCliente, calificar,
};
