const asyncHandler = require('../../shared/helpers/asyncHandler');
const repartidorService = require('./repartidor.service');
const pedidoService = require('../pedidos/pedido.service');

// Controller delgado: la lógica está en repartidor.service.js (y en pedido.service.js para las acciones sobre un
// pedido) y las validaciones en repartidor.schema.js. Las respuestas conservan el formato que ya consume la app.

const crear = asyncHandler(async (req, res) => {
  const resultado = await repartidorService.crear(req.usuario.id, req.body, req);
  res.status(201).json({ message: 'Perfil de repartidor creado exitosamente', ...resultado });
});

const miPerfil = asyncHandler(async (req, res) => res.json(await repartidorService.miPerfil(req.usuario.id, req)));

const actualizar = asyncHandler(async (req, res) => {
  const resultado = await repartidorService.actualizar(req.usuario.id, req.body, req);
  res.json({ message: 'Perfil actualizado exitosamente', ...resultado });
});

const subirFotoPerfil = asyncHandler(async (req, res) => {
  const foto = await repartidorService.cambiarFoto(req.usuario.id, req.body.foto, req);
  res.json({ message: 'Foto de perfil actualizada correctamente', foto });
});

const cambiarDisponibilidad = asyncHandler(async (req, res) => {
  const disponible = req.body.disponible === true || req.body.disponible === 'true';
  const resultado = await repartidorService.cambiarDisponibilidad(req.usuario.id, disponible, req);
  res.json({ message: `Disponibilidad ${disponible ? 'activada' : 'desactivada'} exitosamente`, repartidor: resultado.repartidor });
});

// Ruta que la app usaba y no existía: PATCH /estado { estado: 'disponible' | 'ocupado' }
const cambiarEstado = asyncHandler(async (req, res) => {
  const disponible = req.body.estado === 'disponible';
  const resultado = await repartidorService.cambiarDisponibilidad(req.usuario.id, disponible, req);
  res.json({ message: `Estado actualizado: ${disponible ? 'disponible' : 'no disponible'}`, repartidor: resultado.repartidor });
});

const actualizarUbicacion = asyncHandler(async (req, res) => {
  const ubicacion = await repartidorService.actualizarUbicacion(req.usuario.id, req.body, req);
  res.json({ message: 'Ubicación actualizada exitosamente', ubicacion });
});

const obtenerUbicacion = asyncHandler(async (req, res) => res.json(await repartidorService.ubicacion(req.usuario, req.params.id)));

const pendientes = asyncHandler(async (req, res) => res.json(await repartidorService.pendientes(req.usuario.id, req)));
const pedidosVista = asyncHandler(async (req, res) => res.json(await repartidorService.pedidosVista(req.usuario.id, req)));
const misPedidos = asyncHandler(async (req, res) => res.json(await repartidorService.misPedidos(req.usuario.id, req)));
const entregasActivas = asyncHandler(async (req, res) => res.json(await repartidorService.entregasActivas(req.usuario.id, req)));

const aceptarPedido = asyncHandler(async (req, res) => {
  const resultado = await pedidoService.aceptarRepartidor(req.usuario, req.params.id, req.body.costoDelivery, req);
  res.json({ message: 'Pedido aceptado exitosamente', ...resultado });
});

const actualizarEstadoPedido = asyncHandler(async (req, res) => {
  const resultado = await repartidorService.cambiarEstadoPedido(req.usuario, req.params.id, req.body.estado, req);
  res.json({ message: 'Estado actualizado exitosamente', ...resultado });
});

const listarDisponibles = asyncHandler(async (req, res) => res.json(await repartidorService.listarDisponibles(req)));
const listar = asyncHandler(async (req, res) => res.json(await repartidorService.listar(req)));

module.exports = {
  crear, miPerfil, actualizar, subirFotoPerfil, cambiarDisponibilidad, cambiarEstado, actualizarUbicacion, obtenerUbicacion,
  pendientes, pedidosVista, misPedidos, entregasActivas, aceptarPedido, actualizarEstadoPedido, listarDisponibles, listar,
};
