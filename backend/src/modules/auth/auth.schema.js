const { body, param } = require('express-validator');
const { validarEmail, validarCedula, validarTelefono, validarPlaca, validarIdentificador } = require('../../shared/utils/validators');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');
const { ROLESREGISTRABLES } = require('../../shared/constants/codigos');

// Reglas de validación de las rutas de auth. Cada regla se declara UNA vez y se reutiliza.
// Los validadores (email, cédula, teléfono, placa) viven en shared/utils/validators.js.

const MSGTELEFONO = 'El teléfono debe tener 10 dígitos y empezar con 09 (ej: 0991234567)';
const MSGPLACA = 'Placa inválida. Formatos válidos: AB1234 o ABC-123 (2-3 letras + 3-4 números)';

const email = (campo = 'email', origen = body) => origen(campo)
  .trim()
  .customSanitizer(normalizarEmail)
  .custom(validarEmail).withMessage('Formato de email inválido');

const clave = (campo) => body(campo)
  .isString().withMessage('La contraseña es requerida')
  .isLength({ min: 6, max: 72 }).withMessage('La contraseña debe tener entre 6 y 72 caracteres');

const codigo6 = body('code').trim().matches(/^\d{6}$/).withMessage('El código debe tener 6 dígitos');

const registro = [
  body('nombre').trim().notEmpty().withMessage('El nombre es requerido')
    .isLength({ min: 2, max: 100 }).withMessage('Nombre inválido'),
  body('apellido').trim().notEmpty().withMessage('El apellido es requerido')
    .isLength({ max: 100 }).withMessage('Apellido inválido'),
  email(),
  body('telefono').customSanitizer(normalizarTelefono).custom(validarTelefono).withMessage(MSGTELEFONO),
  body('cedula').trim().custom(validarCedula).withMessage('Cédula inválida: verifica los 10 dígitos'),
  clave('password'),
  body('tipoUsuario').isIn(ROLESREGISTRABLES).withMessage('Tipo de usuario inválido'),
  body('nombreNegocio').optional({ values: 'falsy' }).trim().isLength({ max: 200 }).withMessage('Nombre de negocio demasiado largo'),
  // Solo para repartidores
  body('vehiculo').if(body('tipoUsuario').equals('repartidor')).trim()
    .isLength({ min: 2, max: 50 }).withMessage('El tipo de vehículo es requerido (mínimo 2 caracteres)'),
  body('placa').if(body('tipoUsuario').equals('repartidor')).custom(validarPlaca).withMessage(MSGPLACA),
  body('licencia').optional({ values: 'falsy' }).trim().isLength({ max: 30 }).withMessage('Licencia demasiado larga'),
];

// Se puede entrar con el correo O con el usuario (jcayapa). La app envía el valor en "email" (así ya funciona sin
// cambios) o en "usuario"; en ambos casos queda normalizado en req.body.email.
const login = [
  body('email')
    .customSanitizer((valor, { req }) => normalizarEmail(valor ?? req.body.usuario))
    .custom(validarIdentificador).withMessage('Escribe tu correo o tu usuario'),
  body('password').isString().notEmpty().withMessage('La contraseña es requerida'),
];

const correo = [email()];                                           // forgot-password
const verificarCodigo = [email(), codigo6];                         // verify-reset-code y verify-email
const enviarVerificacion = [
  email(),
  body('nombre').optional({ values: 'falsy' }).trim().isLength({ max: 100 }).withMessage('Nombre demasiado largo'),
  body('fcmToken').optional({ values: 'falsy' }).isString().isLength({ max: 500 }).withMessage('Token de notificaciones inválido'),
];
const restablecer = [
  body('resetToken').isString().withMessage('Token y nueva contraseña son requeridos').trim().notEmpty().withMessage('Token y nueva contraseña son requeridos'),
  clave('newPassword'),
];

const actualizarPerfil = [
  body('nombre').optional().trim().notEmpty().withMessage('El nombre no puede estar vacío')
    .isLength({ min: 2, max: 100 }).withMessage('Nombre inválido'),
  body('apellido').optional().trim().notEmpty().withMessage('El apellido no puede estar vacío')
    .isLength({ max: 100 }).withMessage('Apellido inválido'),
  body('telefono').optional().customSanitizer(normalizarTelefono).custom(validarTelefono).withMessage(MSGTELEFONO),
];
const cambiarClave = [
  body('passwordActual').isString().notEmpty().withMessage('La contraseña actual es requerida'),
  clave('passwordNueva'),
];

// Consultas en tiempo real del formulario de registro
const consultaCedula = [param('cedula').custom(validarCedula).withMessage('Cédula inválida')];
const consultaEmail = [email('email', param)];
const consultaPlaca = [param('placa').custom(validarPlaca).withMessage('Placa inválida')];

module.exports = {
  registro, login, correo, verificarCodigo, enviarVerificacion, restablecer,
  actualizarPerfil, cambiarClave, consultaCedula, consultaEmail, consultaPlaca,
};
