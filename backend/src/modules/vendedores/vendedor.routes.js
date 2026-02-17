const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const vendedorController = require('./vendedor.controller');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');


// Subir logo de perfil (base64, igual que cliente)
router.patch('/perfil/logo',
  verificarToken,
  verificarRol('vendedor'),
  vendedorController.subirLogoPerfil
);

// Validaciones
const validacionCrear = [
  body('nombreNegocio')
    .trim()
    .notEmpty().withMessage('El nombre del negocio es requerido')
    .isLength({ min: 3, max: 200 }).withMessage('El nombre debe tener entre 3 y 200 caracteres'),
  body('descripcion')
    .optional()
    .trim(),
  body('categoria')
    .optional()
    .trim(),
  body('costoDelivery')
    .optional()
    .isFloat({ min: 0 }).withMessage('El costo de delivery debe ser mayor a 0'),
  body('radioCobertura')
    .optional()
    .isInt({ min: 1 }).withMessage('El radio de cobertura debe ser mayor a 0')
];

// Rutas públicas (cualquiera puede ver)
router.get('/', vendedorController.listar);
router.get('/:id', vendedorController.obtenerPorId);

// Rutas protegidas (requieren autenticación)
router.post('/', 
  verificarToken, 
  verificarRol('vendedor'), 
  validacionCrear, 
  vendedorController.crear
);

router.get('/perfil/mi-negocio', 
  verificarToken, 
  verificarRol('vendedor'), 
  vendedorController.miPerfil
);

router.put('/perfil/actualizar', 
  verificarToken, 
  verificarRol('vendedor'), 
  vendedorController.actualizar
);

router.delete('/perfil/eliminar', 
  verificarToken, 
  verificarRol('vendedor'), 
  vendedorController.eliminar
);

// Actualizar ubicación del vendedor
router.patch('/perfil/ubicacion',
  verificarToken,
  verificarRol('vendedor'),
  vendedorController.actualizarUbicacion
);

module.exports = router;
