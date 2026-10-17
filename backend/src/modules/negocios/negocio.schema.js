const { body, param, query } = require('express-validator');
const { CATEGORIA } = require('../../shared/constants/codigos');

// Reglas de validación de las rutas de negocios y de "mi negocio".
const CATEGORIAS = Object.values(CATEGORIA);
const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
const id = [param('id').isInt({ min: 1 }).withMessage('ID de negocio inválido')];

const listar = [
  query('categoria').optional().isIn(CATEGORIAS).withMessage('Categoría inválida'),
  query('q').optional().isString().isLength({ max: 60 }).withMessage('Búsqueda demasiado larga'),
  query('abiertos').optional().isIn(['true', 'false']).withMessage('abiertos debe ser true o false'),
  query('page').optional().isInt({ min: 1 }).withMessage('Página inválida'),
  query('limit').optional().isInt({ min: 1, max: 50 }).withMessage('Límite inválido (1 a 50)'),
];

const datos = (requerido) => [
  (requerido ? body('nombre') : body('nombre').optional())
    .isString().withMessage('El nombre del negocio es requerido').trim()
    .isLength({ min: 2, max: 120 }).withMessage('El nombre debe tener entre 2 y 120 caracteres'),
  body('descripcion').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('La descripción es muy larga (máximo 500)'),
  body('categoria').optional().isIn(CATEGORIAS).withMessage('Categoría inválida'),
  body('ruc').optional({ values: 'falsy' }).matches(/^\d{13}$/).withMessage('El RUC debe tener 13 dígitos'),
  body('pedidoMinimo').optional().isFloat({ min: 0, max: 1000 }).withMessage('Pedido mínimo inválido (0 a 1000)').toFloat(),
  body('tiempoPreparacion').optional().isInt({ min: 5, max: 240 }).withMessage('Tiempo de preparación inválido (5 a 240 minutos)').toInt(),
  body('radioKm').optional().isFloat({ gt: 0, max: 50 }).withMessage('Radio de entrega inválido (hasta 50 km)').toFloat(),
];

const local = [
  body('direccion').isString().withMessage('La dirección del local es requerida').trim().notEmpty().withMessage('La dirección del local es requerida')
    .isLength({ max: 500 }).withMessage('La dirección es muy larga'),
  body('referencia').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('La referencia es muy larga'),
  body('latitud').isFloat({ min: -90, max: 90 }).withMessage('Latitud inválida'),
  body('longitud').isFloat({ min: -180, max: 180 }).withMessage('Longitud inválida'),
];

const horarios = [
  body('horarios').isArray({ min: 1, max: 7 }).withMessage('Envía de 1 a 7 días'),
  body('horarios.*.dia').isInt({ min: 1, max: 7 }).withMessage('El día va de 1 (lunes) a 7 (domingo)').toInt(),
  body('horarios.*.cerrado').optional().isBoolean().withMessage('cerrado debe ser true o false').toBoolean(),
  body('horarios.*').custom((h) => {
    if (h.cerrado === true || h.cerrado === 'true') return true;
    if (!HORA.test(h.apertura || '') || !HORA.test(h.cierre || '')) throw new Error('Las horas van en formato HH:MM (ej: 08:30)');
    if (h.apertura === h.cierre) throw new Error('La hora de apertura y de cierre no pueden ser iguales');
    return true;
  }),
  body('horarios').custom((lista) => {
    const dias = lista.map((h) => Number(h.dia));
    if (new Set(dias).size !== dias.length) throw new Error('Hay días repetidos');
    return true;
  }),
];

const estado = [
  body('abierto').optional().isBoolean().withMessage('abierto debe ser true o false').toBoolean(),
  body('aceptaPedidos').optional().isBoolean().withMessage('aceptaPedidos debe ser true o false').toBoolean(),
  body().custom((b) => {
    if (b.abierto === undefined && b.aceptaPedidos === undefined) throw new Error('Envía abierto o aceptaPedidos');
    return true;
  }),
];

const imagen = [body('imagen').isString().withMessage('Envía la imagen').notEmpty().withMessage('Envía la imagen')];

module.exports = { id, listar, crear: datos(true), actualizar: datos(false), local, horarios, estado, imagen };
