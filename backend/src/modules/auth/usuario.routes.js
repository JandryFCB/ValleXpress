const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const usuariosController = require('./usuario.controller');
const { verificarToken } = require('../../middlewares/auth.middleware');
const upload = require('../../middlewares/upload.middleware');


// Validaciones para actualizar perfil
const validacionActualizar = [
  body('nombre')
    .trim()
    .notEmpty().withMessage('El nombre es requerido')
    .isLength({ min: 2, max: 100 }).withMessage('Nombre inválido'),
  body('apellido')
    .trim()
    .notEmpty().withMessage('El apellido es requerido')
    .isLength({ min: 2, max: 100 }).withMessage('Apellido inválido'),
  body('telefono')
    .notEmpty().withMessage('El teléfono es requerido')
    .matches(/^[0-9+\-\s()]+$/).withMessage('Teléfono inválido')
];

// Validaciones para cambiar contraseña
const validacionCambiarContrasena = [
  body('passwordActual')
    .notEmpty().withMessage('La contraseña actual es requerida'),
  body('passwordNueva')
    .isLength({ min: 6 }).withMessage('La nueva contraseña debe tener al menos 6 caracteres'),
  body('confirmarPassword')
    .notEmpty().withMessage('Debe confirmar la contraseña')
    .custom((value, { req }) => {
      if (value !== req.body.passwordNueva) {
        throw new Error('Las contraseñas no coinciden');
      }
      return true;
    })
];

// Todas las rutas requieren autenticación
router.use(verificarToken);

// Obtener perfil del usuario actual
router.get('/perfil', usuariosController.obtenerPerfil);

// Actualizar perfil
router.put('/actualizar', validacionActualizar, usuariosController.actualizarPerfil);

// Cambiar contraseña
router.post('/cambiar-contrasena', validacionCambiarContrasena, usuariosController.cambiarContrasena);

// Subir foto de perfil
router.post('/foto-perfil', upload.single('foto'), usuariosController.subirFotoPerfil);

module.exports = router;
