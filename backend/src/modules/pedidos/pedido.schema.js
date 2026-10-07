const { body, param } = require('express-validator');

// Reglas de validación de las rutas de pedidos.
const id = [param('id').matches(/^PED-\d{8}-\d{6}$/).withMessage('ID de pedido inválido')];

const crear = [
  body('productos').isArray({ min: 1, max: 50 }).withMessage('Debe incluir al menos un producto (máximo 50)'),
  body('productos.*.productoId').matches(/^PRO-\d{6}$/).withMessage('ID del producto inválido'),
  body('productos.*.cantidad').isInt({ min: 1, max: 99 }).withMessage('La cantidad debe estar entre 1 y 99'),
  body('productos.*.notas').optional({ values: 'null' }).isString().isLength({ max: 300 }).withMessage('Las notas del producto son muy largas'),
  body('vendedorId').optional({ values: 'falsy' }).matches(/^VEN-\d{6}$/).withMessage('ID de vendedor inválido'),
  body('metodoPago').isString().trim().notEmpty().withMessage('El método de pago es requerido'),
  body('direccionEntregaId').optional({ values: 'falsy' }).matches(/^DIR-\d{6}$/).withMessage('ID de dirección inválido'),
  body('notasCliente').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('Las notas son muy largas'),
];

// Cambios de estado que puede pedir el vendedor
const estado = [
  ...id,
  body('estado').isIn(['confirmado', 'preparando', 'listo', 'rechazado']).withMessage('Estado inválido'),
  body('motivo').optional({ values: 'null' }).isString().isLength({ max: 200 }).withMessage('El motivo es muy largo'),
];

const cancelar = [...id, body('motivo').optional({ values: 'null' }).isString().isLength({ max: 200 }).withMessage('El motivo es muy largo')];

const aceptar = [
  ...id,
  body('costoDelivery').isFloat({ min: 0, max: 100 }).withMessage('El costo de delivery es requerido y debe estar entre 0 y 100'),
];

const calificar = [
  ...id,
  body('valoracion').isInt({ min: 1, max: 5 }).withMessage('La valoración debe ser un número de 1 a 5'),
  body('comentario').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('El comentario es muy largo'),
  body('tipo').optional().toLowerCase().isIn(['vendedor', 'repartidor']).withMessage('El tipo debe ser vendedor o repartidor'),
];

module.exports = { id, crear, estado, cancelar, aceptar, calificar };
