const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const controller = require('./usuario.controller');
const schema = require('./auth.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken } = require('../../middlewares/auth.middleware');

// Confirmación de la contraseña nueva (la app la envía como confirmarPassword)
const confirmarClave = body('confirmarPassword')
  .notEmpty().withMessage('Debe confirmar la contraseña')
  .custom((valor, { req }) => valor === req.body.passwordNueva).withMessage('Las contraseñas no coinciden');

// Todas las rutas requieren autenticación
router.use(verificarToken);

router.get('/perfil', controller.obtenerPerfil);
router.put('/actualizar', schema.actualizarPerfil, validar, controller.actualizarPerfil);
router.post('/cambiar-contrasena', schema.cambiarClave, confirmarClave, validar, controller.cambiarContrasena);
router.post('/foto-perfil', controller.subirFotoPerfil);   // la foto llega en base64 (JSON) y se valida con sharp

module.exports = router;
