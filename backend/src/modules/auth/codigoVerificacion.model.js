const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TCODIGOSVERIFICACION (simple): códigos de 6 dígitos para verificar el correo o restablecer la clave.
// Solo se inserta y se actualiza su estado. El código va con hash, nunca en claro.
const CodigoVerificacion = sequelize.define('CodigoVerificacion', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'scodigo' },
  proposito: { type: DataTypes.CHAR(3), allowNull: false, field: 'cpropositocodigo' },     // 001 correo · 002 clave
  email: { type: DataTypes.STRING(150), allowNull: false, field: 'correo' },
  usuarioId: { type: DataTypes.STRING(30), field: 'cusuario' },
  codigoHash: { type: DataTypes.STRING(255), allowNull: false, field: 'codigohash' },
  intentos: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 0, field: 'numerointentos' },
  maxIntentos: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 5, field: 'maxintentos' },
  ip: { type: DataTypes.INET, field: 'ipsolicitud' },
  tokenFcm: { type: DataTypes.STRING(255), field: 'tokenfcm' },
  creadoEn: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW, field: 'fcreacion' },
  expiraEn: { type: DataTypes.DATE, allowNull: false, field: 'fexpira' },
  verificadoEn: { type: DataTypes.DATE, field: 'fverificado' },
  usadoEn: { type: DataTypes.DATE, field: 'fusado' },
}, opcionesSimple('TCODIGOSVERIFICACION'));

module.exports = CodigoVerificacion;
