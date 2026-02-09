const Usuario = require('../models/Usuario');

class UsuariosService {
  // Obtener usuario por ID
  async obtenerPorId(id) {
    return await Usuario.findByPk(id, {
      attributes: [
        'id',
        'nombre',
        'apellido',
        'email',
        'telefono',
        'cedula',
        'tipoUsuario',
        'fotoPerfil',
        'createdAt',
        'activo'
      ]
    });
  }

  // Actualizar datos del usuario
  async actualizar(id, datos) {
    const usuario = await Usuario.findByPk(id);
    if (!usuario) {
      return null;
    }

    return await usuario.update(datos);
  }

  // Cambiar contraseña
  async cambiarContrasena(id, passwordNueva) {
    const usuario = await Usuario.findByPk(id);
    if (!usuario) {
      return null;
    }

    return await usuario.update({
      passwordHash: passwordNueva
    });
  }
}

module.exports = new UsuariosService();