const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./notificacion.service');

// Controller delgado: la lógica está en notificacion.service.js y las validaciones en notificacion.schema.js.

const listar = asyncHandler(async (req, res) => res.json(await service.listar(req.usuario.id, req.query)));

const marcarLeida = asyncHandler(async (req, res) => {
  await service.marcarLeida(req.usuario.id, req.params.id);
  res.json({ message: 'Marcada como leída' });
});

// La app envía aquí el token de Firebase de su celular para recibir notificaciones push
const registrarDispositivo = asyncHandler(async (req, res) => {
  await service.registrarDispositivo(req.usuario.id, req.body);
  res.json({ message: 'Dispositivo registrado' });
});

const quitarDispositivo = asyncHandler(async (req, res) => {
  await service.quitarDispositivo(req.usuario.id, req.body.token);
  res.json({ message: 'Dispositivo eliminado' });
});

module.exports = { listar, marcarLeida, registrarDispositivo, quitarDispositivo };
