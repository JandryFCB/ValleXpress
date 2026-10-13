const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./direccion.service');

// Controller delgado: la lógica está en direccion.service.js y las validaciones en direccion.schema.js.
// Las respuestas conservan el formato que ya consume la app.

const tipos = asyncHandler(async (req, res) => res.json({ tipos: await service.tipos() }));

const listar = asyncHandler(async (req, res) => res.json({ direcciones: await service.listar(req.usuario.id) }));

// Sin predeterminada la app espera 404 con { direccion: null }
const predeterminada = asyncHandler(async (req, res) => {
  const direccion = await service.predeterminada(req.usuario.id);
  return direccion ? res.json({ direccion }) : res.status(404).json({ direccion: null });
});

const crear = asyncHandler(async (req, res) =>
  res.status(201).json({ direccion: await service.crear(req.usuario.id, req.body) }));

const actualizar = asyncHandler(async (req, res) =>
  res.json({ direccion: await service.actualizar(req.usuario.id, req.params.id, req.body) }));

const marcarPredeterminada = asyncHandler(async (req, res) =>
  res.json({ direccion: await service.marcarPredeterminada(req.usuario.id, req.params.id) }));

const eliminar = asyncHandler(async (req, res) => {
  await service.eliminar(req.usuario.id, req.params.id);
  res.json({ message: 'Dirección eliminada' });
});

module.exports = { tipos, listar, predeterminada, crear, actualizar, marcarPredeterminada, eliminar };
