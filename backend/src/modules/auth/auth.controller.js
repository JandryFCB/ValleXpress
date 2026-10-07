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

const getProfile = asyncHandler(async (req, res) => {
  res.json({ usuario: await authService.obtenerPerfil(req.usuario.id, req) });
});

const updateProfile = asyncHandler(async (req, res) => {
  const usuario = await authService.actualizarPerfil(req.usuario.id, req.body, req);
  res.json({ message: 'Perfil actualizado exitosamente', usuario });
});

const changePassword = asyncHandler(async (req, res) => {
  await authService.cambiarClave(req.usuario.id, req.body, req);
  res.json({ message: 'Contraseña actualizada exitosamente' });
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

const checkPlaca = asyncHandler(async (req, res) => {
  const exists = await authService.existePlaca(req.params.placa);
  res.json({ exists, message: exists ? 'Esta placa ya está registrada' : 'Placa disponible' });
});

module.exports = {
  register, login, getProfile, updateProfile, changePassword,
  forgotPassword, verifyResetCode, resetPassword,
  sendEmailVerification, verifyEmailCode,
  checkCedula, checkEmail, checkPlaca,
};
