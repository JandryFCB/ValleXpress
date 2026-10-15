const { body, param, query } = require('express-validator');
const { VEHICULOAAPI } = require('../../shared/constants/codigos');

// Reglas de validación de /api/repartidor.
const VEHICULOS = Object.values(VEHICULOAAPI);
const id = [param('id').isInt({ min: 1 }).withMessage('ID de pedido inválido').toInt()];

const perfil = (requerido) => [
  (requerido ? body('vehiculo') : body('vehiculo').optional())
    .customSanitizer((v) => String(v ?? '').trim().toLowerCase()).isIn(VEHICULOS).withMessage(`El vehículo debe ser: ${VEHICULOS.join(', ')}`),
  body('placa').optional({ values: 'null' }).isString().isLength({ max: 12 }).withMessage('Placa demasiado larga'),
  body('color').optional({ values: 'null' }).isString().isLength({ max: 30 }).withMessage('Color demasiado largo'),
];

const disponibilidad = [body('disponible').isBoolean().withMessage('disponible debe ser true o false').toBoolean()];

const ubicacion = [
  body('latitud').isFloat({ min: -90, max: 90 }).withMessage('Latitud inválida').toFloat(),
  body('longitud').isFloat({ min: -180, max: 180 }).withMessage('Longitud inválida').toFloat(),
];

const listado = [
  query('estado').optional().isIn(['activos', 'historial']).withMessage('estado debe ser activos o historial'),
  query('page').optional().isInt({ min: 1 }).withMessage('Página inválida'),
];

module.exports = { id, crear: perfil(true), actualizar: perfil(false), disponibilidad, ubicacion, listado };
