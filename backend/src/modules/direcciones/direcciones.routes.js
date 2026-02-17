const express = require('express');
const { body } = require('express-validator');
const { verificarToken } = require('../../middlewares/auth.middleware');
const direccionesController = require('./direcciones.controller');


const router = express.Router();

// Validaciones comunes
const validacionBase = [
  body('direccion').optional().isString().withMessage('Dirección inválida'),
  body('nombre').optional().isString().isLength({ max: 50 }).withMessage('Nombre muy largo'),
  body('latitud').optional().isFloat().withMessage('Latitud inválida'),
  body('longitud').optional().isFloat().withMessage('Longitud inválida'),
  body('esPredeterminada').optional().isBoolean().withMessage('Valor inválido'),
];

const validacionCrear = [
  body('direccion').notEmpty().withMessage('La dirección es requerida'),
  body('latitud').notEmpty().withMessage('La latitud es requerida').isFloat().withMessage('Latitud inválida'),
  body('longitud').notEmpty().withMessage('La longitud es requerida').isFloat().withMessage('Longitud inválida'),
  body('esPredeterminada').optional().isBoolean().withMessage('Valor inválido'),
];

// Rutas protegidas para el usuario autenticado
router.use(verificarToken);

router.get('/', direccionesController.listar);
router.get('/predeterminada', direccionesController.predeterminada);
router.post('/', validacionCrear, direccionesController.crear);
router.put('/:id', validacionBase, direccionesController.actualizar);
router.patch('/:id/predeterminada', direccionesController.marcarPredeterminada);
router.delete('/:id', direccionesController.eliminar);

module.exports = router;
