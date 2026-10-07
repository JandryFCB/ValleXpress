const Usuario = require('../modules/auth/usuario.model');
const TokenService = require('../shared/services/token.service');
const AppError = require('../shared/errors/AppError');
const asyncHandler = require('../shared/helpers/asyncHandler');

// Verifica el token JWT y carga el usuario en req.usuario.
// Los errores (token inválido/expirado, cuenta desactivada) los convierte el manejador global.
const verificarToken = asyncHandler(async (req, res, next) => {
  const cabecera = req.headers.authorization;
  if (!cabecera || !cabecera.startsWith('Bearer ')) {
    throw AppError.unauthorized('Token no proporcionado', 'TOKENNOPROPORCIONADO');
  }

  const decodificado = TokenService.verificar(cabecera.split(' ')[1]);   // lanza si es inválido o expiró

  const usuario = await Usuario.findByPk(decodificado.id);
  if (!usuario) throw AppError.unauthorized('Usuario no encontrado', 'USUARIONOENCONTRADO');
  if (!usuario.activo) throw AppError.forbidden('Cuenta desactivada', 'CUENTADESACTIVADA');

  req.usuario = usuario;
  next();
});

// Verifica que el usuario tenga uno de los roles indicados: verificarRol('vendedor', 'repartidor')
const verificarRol = (...rolesPermitidos) => (req, res, next) => {
  if (!req.usuario) return next(AppError.unauthorized('No autenticado', 'NOAUTENTICADO'));
  if (!rolesPermitidos.includes(req.usuario.tipoUsuario)) {
    return next(AppError.forbidden('No tiene permisos para realizar esta acción', 'PROHIBIDO'));
  }
  return next();
};

module.exports = { verificarToken, verificarRol };
