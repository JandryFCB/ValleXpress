const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./telefono.service');

// Controller delgado: la lógica está en telefono.service.js y las validaciones en telefono.schema.js.
const listar = asyncHandler(async (req, res) => res.json({ telefonos: await service.listar(req.usuario.id) }));
const tipos = asyncHandler(async (req, res) => res.json({ tipos: await service.tipos() }));
const crear = asyncHandler(async (req, res) => res.status(201).json({ telefono: await service.crear(req.usuario.id, req.body) }));
const actualizar = asyncHandler(async (req, res) =>
  res.json({ telefono: await service.actualizar(req.usuario.id, Number(req.params.id), req.body) }));
const marcarPrincipal = asyncHandler(async (req, res) =>
  res.json({ telefono: await service.marcarPrincipal(req.usuario.id, Number(req.params.id)) }));
const eliminar = asyncHandler(async (req, res) => {
  await service.eliminar(req.usuario.id, Number(req.params.id));
  res.json({ message: 'Teléfono eliminado' });
});

module.exports = { listar, tipos, crear, actualizar, marcarPrincipal, eliminar };
