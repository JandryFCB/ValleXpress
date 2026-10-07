const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');

// Tabla CODIGOVERIFICACION: reemplaza a las dos tablas anteriores (email_verification_codes y
// password_reset_codes). El PROPOSITO distingue: EMAIL | RESETCLAVE | TELEFONO.
// Es una tabla de registro: solo se inserta y se actualiza el estado del código (sin versionado).
// Su clave es un número 1, 2, 3 (ID) que genera la BD.
const CodigoVerificacion = sequelize.define('CodigoVerificacion', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'id' },
  proposito: { type: DataTypes.STRING(12), allowNull: false, field: 'proposito' },
  email: { type: DataTypes.STRING(150), field: 'email' },
  telefono: { type: DataTypes.STRING(20), field: 'telefono' },
  usuarioId: { type: DataTypes.STRING(30), field: 'usuario' },             // USUARIOS.USUARIO
  codigoHash: { type: DataTypes.STRING(255), allowNull: false, field: 'codigohash' },
  expiraEn: { type: DataTypes.DATE, allowNull: false, field: 'expiraen' },
  intentos: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 0, field: 'intentos' },
  maxIntentos: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 5, field: 'maxintentos' },
  verificadoEn: { type: DataTypes.DATE, field: 'verificadoen' },
  usadoEn: { type: DataTypes.DATE, field: 'usadoen' },
  ip: { type: DataTypes.INET, field: 'ip' },
  tokenFcm: { type: DataTypes.TEXT, field: 'tokenfcm' },
  creadoEn: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW, field: 'creadoen' },
}, {
  tableName: 'codigoverificacion',
  freezeTableName: true,
  timestamps: false,
});

module.exports = CodigoVerificacion;
