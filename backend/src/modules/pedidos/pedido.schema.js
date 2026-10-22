const { body, param, query } = require('express-validator');

// Reglas de validación de las rutas de pedidos.
const id = [param('id').isInt({ min: 1 }).withMessage('ID de pedido inválido').toInt()];

const listado = [
  query('estado').optional().isIn(['activos', 'historial']).withMessage('estado debe ser activos o historial'),
  query('page').optional().isInt({ min: 1 }).withMessage('Página inválida'),
  query('limit').optional().isInt({ min: 1, max: 50 }).withMessage('Límite inválido (1 a 50)'),
];

const crear = [
  body('negocioId').isInt({ min: 1 }).withMessage('Indica el negocio').toInt(),
  body('direccionId').isInt({ min: 1 }).withMessage('Elige la dirección de entrega').toInt(),
  body('metodoPago').isString().withMessage('Elige cómo vas a pagar').trim().notEmpty().withMessage('Elige cómo vas a pagar'),
  body('productos').isArray({ min: 1, max: 50 }).withMessage('Agrega al menos un producto (máximo 50)'),
  body('productos.*.productoId').isInt({ min: 1 }).withMessage('Producto inválido').toInt(),
  body('productos.*.cantidad').isInt({ min: 1, max: 99 }).withMessage('La cantidad debe estar entre 1 y 99').toInt(),
  body('productos.*.notas').optional({ values: 'null' }).isString().isLength({ max: 200 }).withMessage('La nota del producto es muy larga (máximo 200)'),
  body('notas').optional({ values: 'null' }).isString().isLength({ max: 300 }).withMessage('Las indicaciones son muy largas (máximo 300)'),
];

// Cambios de estado que puede pedir el negocio
const estadoNegocio = [
  ...id,
  body('estado').isIn(['confirmado', 'preparando', 'listo', 'rechazado']).withMessage('Estado inválido'),
  body('motivo').optional({ values: 'null' }).isString().isLength({ max: 300 }).withMessage('El motivo es muy largo'),
  body('tiempoEstimado').optional({ values: 'null' }).isInt({ min: 5, max: 240 }).withMessage('Tiempo estimado inválido (5 a 240 minutos)').toInt(),
];

// Cotizar el envío de un negocio a una dirección del cliente
const cotizar = [
  query('negocioId').isInt({ min: 1 }).withMessage('Indica el negocio').toInt(),
  query('direccionId').isInt({ min: 1 }).withMessage('Indica la dirección').toInt(),
];

const cancelar = [...id, body('motivo').optional({ values: 'null' }).isString().isLength({ max: 300 }).withMessage('El motivo es muy largo')];

const calificar = [
  ...id,
  body('puntuacion').isInt({ min: 1, max: 5 }).withMessage('La calificación va de 1 a 5 estrellas').toInt(),
  body('comentario').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('El comentario es muy largo (máximo 500)'),
  body('destino').optional().toLowerCase().isIn(['negocio', 'repartidor']).withMessage('Se califica al negocio o al repartidor'),
];

// El cliente sube la foto de su transferencia
const comprobante = [
  ...id,
  body('imagen').isString().withMessage('Adjunta la foto del comprobante').notEmpty().withMessage('Adjunta la foto del comprobante'),
  body('referencia').optional({ values: 'null' }).isString().trim().isLength({ max: 100 }).withMessage('La referencia es muy larga'),
];

// El negocio confirma si le llegó la transferencia
const pago = [
  ...id,
  body('recibido').isBoolean().withMessage('Indica si te llegó el pago').toBoolean(),
  body('motivo').if(body('recibido').equals('false')).isString().withMessage('Cuéntale al cliente qué pasó').trim()
    .isLength({ min: 3, max: 300 }).withMessage('Cuéntale al cliente qué pasó (3 a 300 letras)'),
];

module.exports = { id, listado, cotizar, crear, estadoNegocio, cancelar, calificar, comprobante, pago };
