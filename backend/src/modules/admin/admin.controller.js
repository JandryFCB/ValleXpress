const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./admin.service');
const PedidoService = require('../pedidos/pedido.service');

// Controller delgado: la lógica del panel está en admin.service.js; la de los pedidos, en pedido.service.js.
const id = (req) => Number(req.params.id);

const resumen = asyncHandler(async (req, res) => res.json(await service.resumen()));

const negocios = asyncHandler(async (req, res) => res.json(await service.negocios(req.query, req)));
const aprobacionNegocio = asyncHandler(async (req, res) => res.json({ negocio: await service.cambiarAprobacionNegocio(req.usuario, id(req), req.body, req) }));

const repartidores = asyncHandler(async (req, res) => res.json(await service.repartidores(req.query)));
const aprobacionRepartidor = asyncHandler(async (req, res) =>
  res.json({ repartidor: await service.cambiarAprobacionRepartidor(req.usuario, req.params.usuario, req.body, req) }));

const pedidos = asyncHandler(async (req, res) => res.json(await PedidoService.listarTodos(req.query, req)));
const pedido = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.obtener(req.usuario, id(req), req) }));
const cancelarPedido = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.cancelarComoAdmin(req.usuario, id(req), req.body, req) }));

const usuarios = asyncHandler(async (req, res) => res.json(await service.usuarios(req.query, req)));
const estadoUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.cambiarEstadoUsuario(req.usuario, req.params.usuario, req.body, req) }));

const usuario = asyncHandler(async (req, res) => res.json({ usuario: await service.obtenerUsuario(req.params.usuario, req) }));
const crearUsuario = asyncHandler(async (req, res) => res.status(201).json({ usuario: await service.crearUsuario(req.usuario, req.body, req) }));
const editarUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.editarUsuario(req.usuario, req.params.usuario, req.body, req) }));
const claveUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.ponerClave(req.usuario, req.params.usuario, req.body.clave, req, { enviarCorreo: req.body.enviarCorreo !== false }) }));
const fotoUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.fotoUsuario(req.usuario, req.params.usuario, req.body.imagen, req) }));
const bajaUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.darDeBaja(req.usuario, req.params.usuario, req.body, req) }));
const editarRepartidor = asyncHandler(async (req, res) => res.json({ repartidor: await service.editarRepartidor(req.usuario, req.params.usuario, req.body, req) }));
const resolverDueno = asyncHandler(async (req, res, next) => { await service.resolverDueno(req); next(); });

const perfiles = asyncHandler(async (req, res) => res.json({ perfiles: await service.perfiles() }));
const cambiarPerfil = asyncHandler(async (req, res) => res.json(await service.cambiarPerfil(req.usuario, req.params.rol, req.body, req)));

module.exports = { resumen, negocios, aprobacionNegocio, repartidores, aprobacionRepartidor, pedidos, pedido, cancelarPedido, usuarios, estadoUsuario, perfiles, cambiarPerfil,
  usuario, crearUsuario, editarUsuario, claveUsuario, fotoUsuario, bajaUsuario, editarRepartidor, resolverDueno };
