const asyncHandler = require('../../shared/helpers/asyncHandler');
const authService = require('./auth.service');

// Controller delgado: recibe la petición, llama al servicio y responde. Sin lógica de negocio,
// sin try/catch (asyncHandler pasa cualquier error al manejador global) y sin validaciones (ver auth.schema.js).
// Las respuestas conservan el formato que ya consume la app Flutter.

const register = asyncHandler(async (req, res) => {
  const resultado = await authService.registrar(req.body, req);
  res.status(201).json({ message: 'Usuario registrado exitosamente', ...resultado });
});

const login = asyncHandler(async (req, res) => {
  const resultado = await authService.login(req.body, req);
  res.json({ message: 'Inicio de sesión exitoso', ...resultado });
});

// Sesión persistente: canjea el refresh token por un token de acceso nuevo (y un refresh token nuevo)
const refresh = asyncHandler(async (req, res) => {
  res.json(await authService.refrescar(req.body, req));
});

// Cierra la sesión de este equipo (el refresh token es la credencial, no hace falta el token de acceso)
const logout = asyncHandler(async (req, res) => {
  await authService.cerrarSesion(req.body, req);
  res.json({ message: 'Sesión cerrada' });
});

// Cierra la sesión en todos los equipos del usuario
const logoutAll = asyncHandler(async (req, res) => {
  const resultado = await authService.cerrarTodasLasSesiones(req.usuario.id, req);
  res.json({ message: 'Sesiones cerradas en todos tus dispositivos', ...resultado });
});

const getProfile = asyncHandler(async (req, res) => {
  res.json({ usuario: await authService.obtenerPerfil(req.usuario.id, req) });
});

const updateProfile = asyncHandler(async (req, res) => {
  const usuario = await authService.actualizarPerfil(req.usuario.id, req.body, req);
  res.json({ message: 'Perfil actualizado exitosamente', usuario });
});

// Cambiar la clave cierra las demás sesiones y devuelve una sesión nueva para este equipo
const changePassword = asyncHandler(async (req, res) => {
  const sesion = await authService.cambiarClave(req.usuario.id, req.body, req);
  res.json({ message: 'Contraseña actualizada exitosamente', ...sesion });
});

const forgotPassword = asyncHandler(async (req, res) => {
  res.json(await authService.solicitarCodigoReset(req.body.email, req));
});

const verifyResetCode = asyncHandler(async (req, res) => {
  res.json(await authService.verificarCodigoReset(req.body));
});

const resetPassword = asyncHandler(async (req, res) => {
  await authService.restablecerClave(req.body, req);
  res.json({ message: 'Contraseña actualizada correctamente' });
});

const sendEmailVerification = asyncHandler(async (req, res) => {
  res.json(await authService.enviarCodigoEmail(req.body, req));
});

const verifyEmailCode = asyncHandler(async (req, res) => {
  res.json(await authService.verificarCodigoEmail(req.body));
});

const checkCedula = asyncHandler(async (req, res) => {
  const exists = await authService.existeCedula(req.params.cedula);
  res.json({ exists, message: exists ? 'Esta cédula ya está registrada' : 'Cédula disponible' });
});

const checkEmail = asyncHandler(async (req, res) => {
  const exists = await authService.existeEmail(req.params.email);
  res.json({ exists, message: exists ? 'Este email ya está registrado' : 'Email disponible' });
});

module.exports = {
  register, login, refresh, logout, logoutAll, getProfile, updateProfile, changePassword,
  forgotPassword, verifyResetCode, resetPassword,
  sendEmailVerification, verifyEmailCode,
  checkCedula, checkEmail,
};
