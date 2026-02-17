const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const productoController = require('./producto.controller');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');


// Validaciones
const validacionCrear = [
  body('nombre')
    .trim()
    .notEmpty().withMessage('El nombre del producto es requerido')
    .isLength({ min: 3, max: 200 }).withMessage('El nombre debe tener entre 3 y 200 caracteres'),
  body('descripcion')
    .optional()
    .trim(),
  body('precio')
    .notEmpty().withMessage('El precio es requerido')
    .isFloat({ min: 0 }).withMessage('El precio debe ser mayor a 0'),
  body('categoria')
    .optional()
    .trim(),
  body('disponible')
    .optional()
    .isBoolean().withMessage('Disponible debe ser true o false'),
  body('tiempoPreparacion')
    .optional()
    .isInt({ min: 0 }).withMessage('El tiempo de preparación debe ser mayor a 0')
];

// ✅ Rutas públicas (orden correcto)
router.get('/', productoController.listar);
router.get('/vendedor/:vendedorId', productoController.listarPorVendedor); // antes que /:id

// ✅ Rutas protegidas (ponlas ANTES de /:id para que no choque)
router.get(
  '/mis-productos',
  verificarToken,
  verificarRol('vendedor'),
  productoController.misProductos
);

router.post(
  '/',
  verificarToken,
  verificarRol('vendedor'),
  validacionCrear,
  productoController.crear
);
router.patch(
  '/:id/disponible',
  verificarToken,
  verificarRol('vendedor'),
  productoController.cambiarDisponible
);

router.put(
  '/:id',
  verificarToken,
  verificarRol('vendedor'),
  productoController.actualizar
);

router.delete(
  '/:id',
  verificarToken,
  verificarRol('vendedor'),
  productoController.eliminar
);

// ✅ Esta SIEMPRE al final
router.get('/:id', productoController.obtenerPorId);

module.exports = router;
