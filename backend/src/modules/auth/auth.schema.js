const { body, param, query } = require('express-validator');
const { validarEmail, validarCedula, validarTelefono, validarIdentificador } = require('../../shared/utils/validators');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');
const { ROLESREGISTRABLES, CATEGORIA } = require('../../shared/constants/codigos');

// Reglas de validación de las rutas de auth. Cada regla se declara UNA vez y se reutiliza.
// Los validadores (email, cédula, teléfono, placa) viven en shared/utils/validators.js.

const MSGTELEFONO = 'El teléfono debe tener 10 dígitos y empezar con 09 (ej: 0991234567)';

const email = (campo = 'email', origen = body) => origen(campo)
  .trim()
  .customSanitizer(normalizarEmail)
  .custom(validarEmail).withMessage('Formato de email inválido');

const clave = (campo) => body(campo)
  .isString().withMessage('La contraseña es requerida')
  .isLength({ min: 6, max: 72 }).withMessage('La contraseña debe tener entre 6 y 72 caracteres');

const codigo6 = body('code').trim().matches(/^\d{6}$/).withMessage('El código debe tener 6 dígitos');

const dispositivo = [
  body('dispositivo').optional({ values: 'falsy' }).isString().isLength({ max: 100 }).withMessage('Nombre de dispositivo demasiado largo'),
  body('plataforma').optional({ values: 'falsy' }).isString().toUpperCase().isIn(['ANDROID', 'IOS', 'WEB']).withMessage('Plataforma inválida'),
];

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
  // Solo para vendedores: con estos datos se crea su negocio en el mismo registro
  body('nombreNegocio').optional({ values: 'falsy' }).isString().trim().isLength({ min: 2, max: 120 }).withMessage('El nombre del negocio debe tener entre 2 y 120 caracteres'),
  body('categoriaNegocio').optional({ values: 'falsy' }).isIn(Object.values(CATEGORIA)).withMessage('Categoría de negocio inválida'),
  // Solo para repartidores: con estos datos se crea su perfil de reparto en el mismo registro
  body('vehiculo').optional({ values: 'falsy' }).isString().isLength({ max: 20 }).withMessage('Vehículo inválido'),
  body('placa').optional({ values: 'falsy' }).isString().isLength({ max: 12 }).withMessage('Placa inválida'),
  // Prueba de aceptación: sin marcar "Acepto" no hay registro (queda guardada la versión aceptada)
  body('aceptaTerminos').custom((v) => v === true || v === 'true').withMessage('Debes aceptar los términos y condiciones y la política de privacidad'),
  // Datos del dispositivo (opcionales): se guardan en la sesión para poder mostrar "dispositivos con sesión iniciada"
  ...dispositivo,
];

// Se puede entrar con el correo O con el usuario (jcayapa). La app envía el valor en "email" (así ya funciona sin
// cambios) o en "usuario"; en ambos casos queda normalizado en req.body.email.
const login = [
  body('email')
    .customSanitizer((valor, { req }) => normalizarEmail(valor ?? req.body.usuario))
    .custom(validarIdentificador).withMessage('Escribe tu correo o tu usuario'),
  body('password').isString().notEmpty().withMessage('La contraseña es requerida'),
  body('tipoUsuario').optional({ values: 'falsy' }).isIn(['cliente', 'vendedor', 'repartidor', 'administrador']).withMessage('Perfil inválido'),
  ...dispositivo,
];

// Renovar o cerrar la sesión: el refresh token es obligatorio
const refrescar = [
  body('refreshToken').isString().withMessage('refreshToken es requerido').isLength({ min: 20, max: 200 }).withMessage('refreshToken inválido'),
];

const correo = [email()];                                           // forgot-password
const verificarCodigo = [email(), codigo6];                         // verify-reset-code y verify-email
const enviarVerificacion = [
  email(),
  body('nombre').optional({ values: 'falsy' }).trim().isLength({ max: 100 }).withMessage('Nombre demasiado largo'),
  body('fcmToken').optional({ values: 'falsy' }).isString().isLength({ max: 500 }).withMessage('Token de notificaciones inválido'),
  body('tipoUsuario').optional({ values: 'falsy' }).isIn(['cliente', 'vendedor', 'repartidor']).withMessage('Perfil inválido'),
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
const eliminarCuenta = [body('password').isString().notEmpty().withMessage('Escribe tu contraseña para confirmar')];

const cambiarClave = [
  body('passwordActual').isString().notEmpty().withMessage('La contraseña actual es requerida'),
  clave('passwordNueva'),
];

// Consultas en tiempo real del formulario de registro
const tipoConsulta = query('tipo').optional({ values: 'falsy' }).isIn(['cliente', 'vendedor', 'repartidor']).withMessage('Perfil inválido');
const consultaCedula = [param('cedula').custom(validarCedula).withMessage('Cédula inválida'), tipoConsulta];
const consultaEmail = [email('email', param), tipoConsulta, query('cedula').optional({ values: 'falsy' }).custom(validarCedula).withMessage('Cédula inválida')];

module.exports = {
  registro, login, refrescar, correo, verificarCodigo, enviarVerificacion, restablecer,
  actualizarPerfil, cambiarClave, eliminarCuenta, consultaCedula, consultaEmail,
};
