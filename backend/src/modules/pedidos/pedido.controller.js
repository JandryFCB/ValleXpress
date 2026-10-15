const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./pedido.service');

// Controller delgado: la lógica está en pedido.service.js, el flujo de estados en pedido_estado.service.js y las
// validaciones en pedido.schema.js.
const id = (req) => Number(req.params.id);

// --- Cliente ---
const metodosPago = asyncHandler(async (req, res) => res.json({ metodos: await service.metodosPago() }));
const crear = asyncHandler(async (req, res) => res.status(201).json({ pedido: await service.crear(req.usuario, req.body, req) }));
const misPedidos = asyncHandler(async (req, res) => res.json(await service.listarDelCliente(req.usuario.id, req.query, req)));
const cancelar = asyncHandler(async (req, res) => res.json({ pedido: await service.cancelar(req.usuario, id(req), req.body, req) }));
const recibido = asyncHandler(async (req, res) => res.json({ pedido: await service.marcarRecibido(req.usuario, id(req), req) }));
const calificar = asyncHandler(async (req, res) => res.json({ pedido: await service.calificar(req.usuario, id(req), req.body, req) }));

// --- Cualquier participante (el servicio comprueba que el pedido sea suyo) ---
const obtener = asyncHandler(async (req, res) => res.json({ pedido: await service.obtener(req.usuario, id(req), req) }));

// --- Negocio (rutas en /api/mi-negocio/pedidos) ---
const delNegocio = asyncHandler(async (req, res) => res.json(await service.listarDelNegocio(req.usuario.id, req.query, req)));
const estadoNegocio = asyncHandler(async (req, res) => res.json({ pedido: await service.cambiarEstadoNegocio(req.usuario, id(req), req.body, req) }));

module.exports = { metodosPago, crear, misPedidos, cancelar, recibido, calificar, obtener, delNegocio, estadoNegocio };
