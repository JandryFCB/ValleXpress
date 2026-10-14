// Carga los modelos para que Sequelize los registre. Solo los que ya usan las tablas nuevas
// (database/migraciones); el resto se agrega aquí cuando se migra su módulo.
const { sequelize } = require('./config/database');

const Usuario = require('./modules/auth/usuario.model');                    // vista VUSUARIOS (lectura)
const Persona = require('./modules/auth/persona.model');                    // TPERSONAS
const UsuarioCuenta = require('./modules/auth/usuarioCuenta.model');        // TUSUARIOS
const UsuarioAcceso = require('./modules/auth/usuarioAcceso.model');        // TUSUARIOSACCESO
const Telefono = require('./modules/telefonos/telefono.model');             // TPERSONATELEFONOS
const Direccion = require('./modules/direcciones/direccion.model');         // TPERSONADIRECCIONES
const CodigoVerificacion = require('./modules/auth/codigoVerificacion.model');
const Sesion = require('./modules/auth/sesion.model');

module.exports = {
  sequelize,
  Usuario,
  Persona,
  UsuarioCuenta,
  UsuarioAcceso,
  Telefono,
  Direccion,
  CodigoVerificacion,
  Sesion,
};
