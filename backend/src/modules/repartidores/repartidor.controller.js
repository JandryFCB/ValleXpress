const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./repartidor.service');
const PedidoService = require('../pedidos/pedido.service');

// Controller delgado: el perfil está en repartidor.service.js; las acciones sobre pedidos, en pedido.service.js.
const u = (req) => req.usuario.id;
const id = (req) => Number(req.params.id);

// --- Perfil ---
const miPerfil = asyncHandler(async (req, res) => res.json({ repartidor: await service.miPerfil(u(req)) }));
const crear = asyncHandler(async (req, res) => res.status(201).json({ repartidor: await service.crear(u(req), req.body, req) }));
const actualizar = asyncHandler(async (req, res) => res.json({ repartidor: await service.actualizar(u(req), req.body, req) }));
const disponibilidad = asyncHandler(async (req, res) => res.json({ repartidor: await service.cambiarDisponibilidad(u(req), req.body.disponible, req) }));
const ubicacion = asyncHandler(async (req, res) =>
  res.json(await service.registrarUbicacion(u(req), { lat: req.body.latitud, lng: req.body.longitud }, req.io)));

// --- Pedidos ---
const libres = asyncHandler(async (req, res) => res.json(await PedidoService.libresParaRepartidor(u(req), req)));
const misEntregas = asyncHandler(async (req, res) => res.json(await PedidoService.listarDelRepartidor(u(req), req.query, req)));
const aceptar = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.aceptar(req.usuario, id(req), req) }));
const recoger = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.recoger(req.usuario, id(req), req) }));
const entregar = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.entregar(req.usuario, id(req), req) }));

module.exports = { miPerfil, crear, actualizar, disponibilidad, ubicacion, libres, misEntregas, aceptar, recoger, entregar };
