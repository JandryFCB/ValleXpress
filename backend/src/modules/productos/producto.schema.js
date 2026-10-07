const { body, param, query } = require('express-validator');

// Reglas de validación de las rutas de productos.
const campos = (obligatorios) => {
  const regla = (campo) => (obligatorios ? body(campo) : body(campo).optional());
  return [
    regla('nombre').trim().notEmpty().withMessage('El nombre del producto es requerido')
      .isLength({ min: 3, max: 200 }).withMessage('El nombre debe tener entre 3 y 200 caracteres'),
    body('descripcion').optional({ values: 'null' }).isString().isLength({ max: 2000 }).withMessage('La descripción es demasiado larga'),
    regla('precio').notEmpty().withMessage('El precio es requerido')
      .isFloat({ min: 0, max: 99999 }).withMessage('El precio debe ser un valor entre 0 y 99999'),
    body('categoria').optional({ values: 'null' }).trim().isLength({ max: 100 }).withMessage('La categoría es demasiado larga'),
    body('disponible').optional().isBoolean().withMessage('Disponible debe ser true o false'),
    body('tiempoPreparacion').optional({ values: 'null' }).isInt({ min: 0, max: 1000 }).withMessage('El tiempo de preparación debe ser un número de minutos entre 0 y 1000'),
    body('stock').optional({ values: 'null' }).isInt({ min: 0, max: 1000000 }).withMessage('El stock debe ser un número entero mayor o igual a 0'),
    body('imagen').optional({ values: 'null' }).isString().withMessage('La imagen no es válida'),
  ];
};

const crear = campos(true);
const actualizar = campos(false);

const id = [param('id').matches(/^PRO-\d{6}$/).withMessage('ID de producto inválido')];
const vendedorId = [param('vendedorId').matches(/^VEN-\d{6}$/).withMessage('ID de vendedor inválido')];

const disponible = [
  ...id,
  body('disponible').custom((v) => typeof v === 'boolean').withMessage('Disponible debe ser boolean'),
];

const paginacion = [
  query('limite').optional().isInt({ min: 1, max: 500 }).withMessage('El límite debe estar entre 1 y 500'),
  query('pagina').optional().isInt({ min: 1 }).withMessage('La página debe ser 1 o mayor'),
];

module.exports = { crear, actualizar, id, vendedorId, disponible, paginacion };
