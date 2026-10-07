const asyncHandler = require('../../shared/helpers/asyncHandler');
const AppError = require('../../shared/errors/AppError');
const authService = require('./auth.service');

// Perfil del usuario autenticado (/api/usuarios). Delgado: toda la lógica está en auth.service.js.
// Formato de respuesta { success, data } que ya usa la app.

const obtenerPerfil = asyncHandler(async (req, res) => {
  res.json({ success: true, data: await authService.obtenerPerfil(req.usuario.id, req) });
});

const actualizarPerfil = asyncHandler(async (req, res) => {
  const u = await authService.actualizarPerfil(req.usuario.id, req.body, req);
  res.json({
    success: true,
    message: 'Perfil actualizado correctamente',
    data: { id: u.id, nombre: u.nombre, apellido: u.apellido, email: u.email, telefono: u.telefono, cedula: u.cedula, tipoUsuario: u.tipoUsuario },
  });
});

const cambiarContrasena = asyncHandler(async (req, res) => {
  await authService.cambiarClave(req.usuario.id, req.body, req);
  res.json({ success: true, message: 'Contraseña actualizada correctamente' });
});

// La foto llega en base64 (como la envía la app); se optimiza a WebP, se guarda en disco y su código en ARCHIVOS.
const subirFotoPerfil = asyncHandler(async (req, res) => {
  if (!req.body.foto) throw AppError.badRequest('No se proporcionó foto', 'IMAGENVACIA');
  const fotoPerfil = await authService.subirFoto(req.usuario.id, req.body.foto, req);
  res.json({ success: true, message: 'Foto de perfil actualizada correctamente', data: { fotoPerfil } });
});

module.exports = { obtenerPerfil, actualizarPerfil, cambiarContrasena, subirFotoPerfil };
