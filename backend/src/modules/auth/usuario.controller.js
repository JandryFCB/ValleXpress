const { validationResult } = require('express-validator');
const usuariosService = require('../../services/usuarios.service');
const Usuario = require('./usuario.model');




class UsuariosController {
  // Obtener perfil del usuario actual
  async obtenerPerfil(req, res) {
    try {
      const usuario = await usuariosService.obtenerPorId(req.usuario.id);

      if (!usuario) {
        return res.status(404).json({
          success: false,
          error: 'Usuario no encontrado'
        });
      }

      res.json({
        success: true,
        data: usuario
      });
    } catch (error) {
      console.error('Error al obtener perfil:', error);
      res.status(500).json({
        success: false,
        error: 'Error al obtener perfil del usuario'
      });
    }
  }

  // Actualizar perfil del usuario
  async actualizarPerfil(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          errors: errors.array()
        });
      }

      const { nombre, apellido, telefono } = req.body;

      const usuarioActualizado = await usuariosService.actualizar(req.usuario.id, {
        nombre,
        apellido,
        telefono
      });

      if (!usuarioActualizado) {
        return res.status(404).json({
          success: false,
          error: 'Usuario no encontrado'
        });
      }

      res.json({
        success: true,
        message: 'Perfil actualizado correctamente',
        data: {
          id: usuarioActualizado.id,
          nombre: usuarioActualizado.nombre,
          apellido: usuarioActualizado.apellido,
          email: usuarioActualizado.email,
          telefono: usuarioActualizado.telefono,
          cedula: usuarioActualizado.cedula,
          tipoUsuario: usuarioActualizado.tipoUsuario
        }
      });
    } catch (error) {
      console.error('Error al actualizar perfil:', error);
      res.status(500).json({
        success: false,
        error: 'Error al actualizar perfil'
      });
    }
  }

  // Cambiar contraseña
  async cambiarContrasena(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          errors: errors.array()
        });
      }

      const { passwordActual, passwordNueva } = req.body;

      // Obtener usuario con password_hash
      const usuario = await Usuario.findByPk(req.usuario.id);

      if (!usuario) {
        return res.status(404).json({
          success: false,
          error: 'Usuario no encontrado'
        });
      }

      // Verificar contraseña actual - IMPORTANTE: usar el método del modelo
      const passwordValido = await usuario.verificarPassword(passwordActual);

      if (!passwordValido) {
        return res.status(401).json({
          success: false,
          error: 'Contraseña actual incorrecta'
        });
      }

      // Cambiar contraseña
      await usuariosService.cambiarContrasena(req.usuario.id, passwordNueva);

      res.json({
        success: true,
        message: 'Contraseña actualizada correctamente'
      });
    } catch (error) {
      console.error('Error al cambiar contraseña:', error);
      res.status(500).json({
        success: false,
        error: 'Error al cambiar contraseña'
      });
    }
  }
  // Subir foto de perfil
async subirFotoPerfil(req, res) {
  try {
    const { foto } = req.body;
    console.log('Foto length:', foto.length);
    if (!foto) {
      return res.status(400).json({
        success: false,
        error: 'No se proporcionó foto'
      });
    }

    const usuario = await usuariosService.obtenerPorId(req.usuario.id);

    if (!usuario) {
      return res.status(404).json({
        success: false,
        error: 'Usuario no encontrado'
      });
    }

    // Guardar base64 directamente
    const usuarioActualizado = await usuariosService.actualizar(req.usuario.id, {
      fotoPerfil: foto
    });

    res.json({
      success: true,
      message: 'Foto de perfil actualizada correctamente',
      data: {
        fotoPerfil: usuarioActualizado.fotoPerfil
      }
    });
  } catch (error) {
    console.error('Error al subir foto:', error);
    res.status(500).json({
      success: false,
      error: 'Error al subir foto de perfil'
    });
  }
}
}
module.exports = new UsuariosController();
