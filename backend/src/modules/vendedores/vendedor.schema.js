const { body, param } = require('express-validator');

// Reglas de validación de las rutas de vendedores.
const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
const MSGHORA = 'La hora debe tener el formato HH:MM (ej: 08:30)';
const vacio = { values: 'falsy' };

const id = [param('id').matches(/^VEN-\d{6}$/).withMessage('ID de vendedor inválido')];

const crear = [
  body('nombreNegocio').trim().notEmpty().withMessage('El nombre del negocio es requerido')
    .isLength({ min: 3, max: 200 }).withMessage('El nombre debe tener entre 3 y 200 caracteres'),
  body('descripcion').optional().trim().isLength({ max: 2000 }).withMessage('La descripción es demasiado larga'),
  body('categoria').optional().trim().isLength({ max: 100 }).withMessage('La categoría es demasiado larga'),
  body('costoDelivery').optional().isFloat({ min: 0, max: 999 }).withMessage('El costo de delivery debe ser un valor entre 0 y 999'),
  body('radioCobertura').optional().isFloat({ min: 0.1, max: 500 }).withMessage('El radio de cobertura debe ser mayor a 0'),
];

const actualizar = [
  body('nombreNegocio').optional(vacio).trim().isLength({ min: 3, max: 200 }).withMessage('El nombre debe tener entre 3 y 200 caracteres'),
  body('descripcion').optional().isString().isLength({ max: 2000 }).withMessage('La descripción es demasiado larga'),
  body('categoria').optional(vacio).trim().isLength({ max: 100 }).withMessage('La categoría es demasiado larga'),
  body('costoDelivery').optional().isFloat({ min: 0, max: 999 }).withMessage('El costo de delivery debe ser un valor entre 0 y 999'),
  body('radioCobertura').optional(vacio).isFloat({ min: 0.1, max: 500 }).withMessage('El radio de cobertura debe ser mayor a 0'),
  body('abiertoAhora').optional().isBoolean().withMessage('abiertoAhora debe ser true o false'),
  body('horarioApertura').optional(vacio).matches(HORA).withMessage(MSGHORA),
  body('horarioCierre').optional(vacio).matches(HORA).withMessage(MSGHORA),
];

const ubicacion = [
  body('latitud').exists({ values: 'null' }).withMessage('Latitud y longitud son requeridas')
    .bail().isFloat({ min: -90, max: 90 }).withMessage('La latitud debe estar entre -90 y 90'),
  body('longitud').exists({ values: 'null' }).withMessage('Latitud y longitud son requeridas')
    .bail().isFloat({ min: -180, max: 180 }).withMessage('La longitud debe estar entre -180 y 180'),
];

const logo = [body('logo').isString().notEmpty().withMessage('No se proporcionó logo')];
const banner = [body('banner').isString().notEmpty().withMessage('No se proporcionó banner')];

module.exports = { id, crear, actualizar, ubicacion, logo, banner };
