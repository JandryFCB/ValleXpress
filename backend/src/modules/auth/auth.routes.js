const express = require('express');
const router = express.Router();
const controller = require('./auth.controller');
const schema = require('./auth.schema');
const validar = require('../../shared/middlewares/validar');
const limite = require('../../shared/middlewares/limitadores');
const { verificarToken } = require('../../middlewares/auth.middleware');

// Cada ruta lista, en orden: límite de peticiones -> reglas de validación -> validar -> controller.

// --- Públicas ---
router.get('/registro/perfiles', limite.consultas(), controller.perfilesRegistro);
router.post('/register', limite.registro(), schema.registro, validar, controller.register);
router.post('/login', limite.login(), schema.login, validar, controller.login);

// Sesión persistente: renovar y cerrar (el refresh token es la credencial)
router.post('/refresh', limite.refrescar(), schema.refrescar, validar, controller.refresh);
router.post('/logout', schema.refrescar, validar, controller.logout);

// Recuperar contraseña
router.post('/forgot-password', limite.enviarCodigo(), schema.correo, validar, controller.forgotPassword);
router.post('/verify-reset-code', limite.verificarCodigo(), schema.verificarCodigo, validar, controller.verifyResetCode);
router.post('/reset-password', limite.restablecer(), schema.restablecer, validar, controller.resetPassword);

// Verificación de email (antes de registrarse)
router.post('/send-verification', limite.enviarCodigo(), schema.enviarVerificacion, validar, controller.sendEmailVerification);
router.post('/verify-email', limite.verificarCodigo(), schema.verificarCodigo, validar, controller.verifyEmailCode);

// Validación en tiempo real de campos únicos
router.get('/check-cedula/:cedula', limite.consultas(), schema.consultaCedula, validar, controller.checkCedula);
router.get('/check-email/:email', limite.consultas(), schema.consultaEmail, validar, controller.checkEmail);

// --- Protegidas ---
router.post('/logout-all', verificarToken, controller.logoutAll);
router.get('/profile', verificarToken, controller.getProfile);
router.get('/cuentas', verificarToken, controller.cuentas);
router.put('/profile', verificarToken, schema.actualizarPerfil, validar, controller.updateProfile);
router.put('/change-password', verificarToken, schema.cambiarClave, validar, controller.changePassword);
router.post('/eliminar-cuenta', verificarToken, limite.login(), schema.eliminarCuenta, validar, controller.deleteAccount);

module.exports = router;
