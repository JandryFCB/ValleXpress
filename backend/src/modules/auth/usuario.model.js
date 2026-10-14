const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { ROLAAPI } = require('../../shared/constants/codigos');

// Vista VUSUARIOS (SOLO LECTURA): usuario + persona + teléfono principal + acceso, con lo vigente de cada tabla.
// Para escribir se usan Persona, UsuarioCuenta, UsuarioAcceso y Telefono. Los atributos conservan los nombres que usa
// el resto del backend y la app (id, nombre, apellido, email, telefono, cedula, tipoUsuario...).
const Usuario = sequelize.define('Usuario', {
  id: { type: DataTypes.STRING(30), primaryKey: true, field: 'usuario' },                // jcayapa
  personaId: { type: DataTypes.BIGINT, field: 'cpersona' },
  rol: { type: DataTypes.CHAR(3), field: 'rol' },
  estatus: { type: DataTypes.CHAR(3), field: 'estatus' },
  activo: { type: DataTypes.BOOLEAN, field: 'activo' },
  nombre: { type: DataTypes.STRING(100), field: 'nombres' },
  apellido: { type: DataTypes.STRING(100), field: 'apellidos' },
  email: { type: DataTypes.STRING(150), field: 'email' },
  verificado: { type: DataTypes.BOOLEAN, field: 'emailverif' },
  tipoDoc: { type: DataTypes.CHAR(3), field: 'tipodoc' },
  cedula: { type: DataTypes.STRING(20), field: 'numdoc' },
  telefono: { type: DataTypes.STRING(20), field: 'telefono' },
  passwordHash: { type: DataTypes.STRING(255), field: 'clavehash' },
  claveCambiadaEn: { type: DataTypes.DATE, field: 'clavecambiadaen' },
  terminosEn: { type: DataTypes.DATE, field: 'terminosen' },
  terminosVer: { type: DataTypes.STRING(20), field: 'terminosver' },
  intentosFallidos: { type: DataTypes.SMALLINT, field: 'intentosfallidos' },
  bloqueadoHasta: { type: DataTypes.DATE, field: 'bloqueadohasta' },
  ultimaConexion: { type: DataTypes.DATE, field: 'ultimaconexion' },
  creadoEn: { type: DataTypes.DATE, field: 'creadoen' },
  fotoId: { type: DataTypes.BIGINT, field: 'foto' },                              // TARCHIVOS

  // El mismo valor que "id", con el nombre que usa la API: "usuario" (jcayapa). No es una columna.
  usuario: {
    type: DataTypes.VIRTUAL(DataTypes.STRING, ['id']),
    get() { return this.getDataValue('id'); },
  },

  // 'cliente' | 'vendedor' | 'repartidor' | 'administrador' (la app y los tokens hablan en texto)
  tipoUsuario: {
    type: DataTypes.VIRTUAL(DataTypes.STRING, ['rol']),
    get() { return ROLAAPI[this.getDataValue('rol')]; },
  },
}, {
  tableName: 'vusuarios',
  freezeTableName: true,
  timestamps: false,
});

Usuario.prototype.verificarClave = function verificarClave(clave) {
  // require perezoso para no crear un ciclo con utils/clave
  return require('../../shared/utils/clave').compararClave(clave, this.passwordHash);
};

// Nunca devolver el hash de la clave
Usuario.prototype.toJSON = function toJSON() {
  const valores = { ...this.get() };
  delete valores.passwordHash;
  return valores;
};

module.exports = Usuario;
