const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const authController = require('../controllers/auth.controller');
const { verificarToken } = require('../middlewares/auth.middleware');
const rateLimit = require('express-rate-limit');

// Validaciones para registro
const validacionRegistro = [
  body('nombre')
    .trim()
    .notEmpty().withMessage('El nombre es requerido')
    .isLength({ min: 2, max: 100 }).withMessage('Nombre inválido'),
  body('apellido')
    .trim()
    .notEmpty().withMessage('El apellido es requerido'),
  body('email').trim().isEmail().withMessage('Email inválido').normalizeEmail(),

  body('telefono')
    .optional()
    .matches(/^[0-9+\-\s()]+$/).withMessage('Teléfono inválido'),
  body('password')
    .isLength({ min: 6 }).withMessage('La contraseña debe tener al menos 6 caracteres'),
  body('tipoUsuario')
    .isIn(['cliente', 'vendedor', 'repartidor']).withMessage('Tipo de usuario inválido')
];

// ✅ Validaciones para login (ESTO ES LO QUE TE FALTÓ)
const validacionLogin = [
  body('email')
    .trim()
    .isEmail().withMessage('Email inválido')
    .normalizeEmail(),
  body('password')
    .notEmpty().withMessage('La contraseña es requerida')
];

// Rate limiters
const forgotPasswordLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  message: { error: 'Demasiadas solicitudes. Intenta en 1 minuto.' }
});

const verifyCodeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { error: 'Demasiados intentos. Intenta en 1 minuto.' }
});

const resetPasswordLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { error: 'Demasiados intentos. Intenta en 1 minuto.' }
});

const emailVerificationLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  message: { error: 'Demasiadas solicitudes. Intenta en 1 minuto.' }
});


// Rutas públicas
router.post('/register', validacionRegistro, authController.register);
router.post('/login', validacionLogin, authController.login);

router.post('/forgot-password', forgotPasswordLimiter, authController.forgotPassword);
router.post('/verify-reset-code', verifyCodeLimiter, authController.verifyResetCode);
router.post('/reset-password', resetPasswordLimiter, authController.resetPassword);

// Verificación de email
router.post('/send-verification', emailVerificationLimiter, authController.sendEmailVerification);
router.post('/verify-email', verifyCodeLimiter, authController.verifyEmailCode);

// ✅ Validación en tiempo real de campos únicos (sin autenticación)
router.get('/check-cedula/:cedula', authController.checkCedula);
router.get('/check-email/:email', authController.checkEmail);
router.get('/check-placa/:placa', authController.checkPlaca);

// Rutas protegidas

router.get('/profile', verificarToken, authController.getProfile);
router.put('/profile', verificarToken, authController.updateProfile);
router.put('/change-password', verificarToken, authController.changePassword);

module.exports = router;
