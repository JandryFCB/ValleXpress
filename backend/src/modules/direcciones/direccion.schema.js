const { body, param } = require('express-validator');

// Reglas de validación de las rutas de direcciones.
const ID = [param('id').matches(/^DIR-\d{6}$/).withMessage('ID de dirección inválido')];

const opcionales = [
  body('nombre').optional({ values: 'null' }).isString().isLength({ max: 50 }).withMessage('El nombre es muy largo (máximo 50)'),
  body('referencia').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('La referencia es muy larga'),
  body('instrucciones').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('Las instrucciones son muy largas'),
  body('esPredeterminada').optional().isBoolean().withMessage('esPredeterminada debe ser true o false'),
];

const crear = [
  body('direccion').isString().trim().notEmpty().withMessage('La dirección es requerida')
    .isLength({ max: 500 }).withMessage('La dirección es muy larga'),
  body('latitud').notEmpty().withMessage('La latitud es requerida').bail().isFloat({ min: -90, max: 90 }).withMessage('Latitud inválida'),
  body('longitud').notEmpty().withMessage('La longitud es requerida').bail().isFloat({ min: -180, max: 180 }).withMessage('Longitud inválida'),
  ...opcionales,
];

const actualizar = [
  ...ID,
  body('direccion').optional().isString().trim().notEmpty().withMessage('La dirección no puede estar vacía')
    .isLength({ max: 500 }).withMessage('La dirección es muy larga'),
  body('latitud').optional().isFloat({ min: -90, max: 90 }).withMessage('Latitud inválida'),
  body('longitud').optional().isFloat({ min: -180, max: 180 }).withMessage('Longitud inválida'),
  ...opcionales,
];

module.exports = { id: ID, crear, actualizar };
