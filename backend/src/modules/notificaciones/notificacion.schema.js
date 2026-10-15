const { body, param, query } = require('express-validator');

// Reglas de validación de las rutas de notificaciones.
const id = [param('id').isInt({ min: 1 }).withMessage('ID de notificación inválido')];

const listado = [
  query('limite').optional().isInt({ min: 1, max: 100 }).withMessage('El límite debe estar entre 1 y 100'),
  query('pagina').optional().isInt({ min: 1 }).withMessage('La página debe ser 1 o mayor'),
];

const dispositivo = [
  body('token').isString().withMessage('El token es requerido').trim().notEmpty().withMessage('El token es requerido')
    .isLength({ max: 255 }).withMessage('El token es demasiado largo'),
  body('plataforma').optional().toLowerCase().isIn(['android', 'ios', 'web']).withMessage('Plataforma inválida (android, ios o web)'),
  body('modelo').optional({ values: 'null' }).isString().isLength({ max: 100 }).withMessage('Modelo demasiado largo'),
  body('appVer').optional({ values: 'null' }).isString().isLength({ max: 20 }).withMessage('Versión demasiado larga'),
];

const quitarDispositivo = [body('token').isString().withMessage('El token es requerido').trim().notEmpty().withMessage('El token es requerido')];

module.exports = { id, listado, dispositivo, quitarDispositivo };
