const { body, param } = require('express-validator');
const { validarPlaca } = require('../../shared/utils/validators');

// Reglas de validación de las rutas de repartidores.
const MSGPLACA = 'Placa inválida. Formatos válidos: AB1234 o ABC-123 (2-3 letras + 3-4 números)';
const ID = [param('id').matches(/^PED-\d{8}-\d{6}$/).withMessage('ID de pedido inválido')];

const crear = [
  body('vehiculo').isString().trim().isLength({ min: 2, max: 50 }).withMessage('El vehículo es requerido (mínimo 2 caracteres)'),
  body('placa').custom(validarPlaca).withMessage(MSGPLACA),
  body('licencia').optional({ values: 'falsy' }).isString().trim().isLength({ max: 30 }).withMessage('Licencia demasiado larga'),
];

const actualizar = [
  body('vehiculo').optional({ values: 'falsy' }).isString().trim().isLength({ min: 2, max: 50 }).withMessage('El vehículo debe tener entre 2 y 50 caracteres'),
  body('placa').optional({ values: 'falsy' }).custom(validarPlaca).withMessage(MSGPLACA),
  body('licencia').optional({ values: 'falsy' }).isString().trim().isLength({ max: 30 }).withMessage('Licencia demasiado larga'),
];

const disponibilidad = [
  body('disponible').exists({ values: 'null' }).withMessage('El campo disponible es requerido')
    .bail().isBoolean().withMessage('Debe ser true o false'),
];

// PATCH /estado (la app lo usa para cambiar su disponibilidad): disponible | ocupado | inactivo ...
const estadoDisponibilidad = [
  body('estado').isIn(['disponible', 'ocupado', 'no_disponible', 'inactivo']).withMessage('Estado no válido. Usa: disponible u ocupado'),
];

const ubicacion = [
  body('latitud').exists({ values: 'null' }).withMessage('La latitud es requerida').bail().isFloat({ min: -90, max: 90 }).withMessage('Latitud inválida'),
  body('longitud').exists({ values: 'null' }).withMessage('La longitud es requerida').bail().isFloat({ min: -180, max: 180 }).withMessage('Longitud inválida'),
];

const foto = [body('foto').isString().notEmpty().withMessage('No se proporcionó foto')];

const aceptar = [
  ...ID,
  body('costoDelivery').isFloat({ min: 0, max: 100 }).withMessage('El costo de delivery es requerido y debe estar entre 0 y 100'),
];

const estadoPedido = [
  ...ID,
  body('estado').isIn(['en_camino', 'entregado']).withMessage('Estado no válido. Usa: en_camino o entregado'),
];

const ubicacionDe = [param('id').matches(/^[a-z0-9]{3,30}$/).withMessage('ID de repartidor inválido')];

module.exports = { crear, actualizar, disponibilidad, estadoDisponibilidad, ubicacion, foto, aceptar, estadoPedido, ubicacionDe };
