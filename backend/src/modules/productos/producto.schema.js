const { body, param } = require('express-validator');

// Reglas de validación de los productos del vendedor.
const ESTADOS = ['disponible', 'agotado', 'oculto'];
const id = [param('id').isInt({ min: 1 }).withMessage('ID de producto inválido')];

const campos = (requerido) => [
  (requerido ? body('nombre') : body('nombre').optional())
    .isString().withMessage('El nombre es requerido').trim()
    .isLength({ min: 2, max: 120 }).withMessage('El nombre debe tener entre 2 y 120 caracteres'),
  (requerido ? body('precio') : body('precio').optional())
    .isFloat({ gt: 0, lt: 10000 }).withMessage('El precio debe ser mayor que 0 (y menor que 10000)').toFloat(),
  body('descripcion').optional({ values: 'null' }).isString().isLength({ max: 500 }).withMessage('La descripción es muy larga (máximo 500)'),
  body('seccion').optional({ values: 'null' }).isString().isLength({ max: 60 }).withMessage('La sección es muy larga (máximo 60)'),
  body('estado').optional().isIn(ESTADOS).withMessage('El estado debe ser disponible, agotado u oculto'),
  body('orden').optional().isInt({ min: 0, max: 999 }).withMessage('Orden inválido').toInt(),
  body('controlaStock').optional().isBoolean().withMessage('controlaStock debe ser true o false').toBoolean(),
  body('stock').optional().isInt({ min: 0, max: 100000 }).withMessage('Stock inválido').toInt(),
  body('imagen').optional({ values: 'null' }).isString().withMessage('Imagen inválida'),
];

module.exports = {
  id,
  crear: campos(true),
  actualizar: [...id, ...campos(false)],
  estado: [...id, body('estado').isIn(ESTADOS).withMessage('El estado debe ser disponible, agotado u oculto')],
  stock: [...id, body('stock').isInt({ min: 0, max: 100000 }).withMessage('El stock debe ser un número entero de 0 en adelante').toInt()],
  imagen: [...id, body('imagen').isString().withMessage('Envía la imagen').notEmpty().withMessage('Envía la imagen')],
};
