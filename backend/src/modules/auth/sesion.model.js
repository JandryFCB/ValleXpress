const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TSESIONES (simple): una fila por refresh token. Solo se guarda el HASH del token (nunca el token).
const Sesion = sequelize.define('Sesion', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'ssesion' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  familia: { type: DataTypes.UUID, allowNull: false, field: 'cfamilia' },
  tokenHash: { type: DataTypes.CHAR(64), allowNull: false, field: 'tokenhash' },
  dispositivo: { type: DataTypes.STRING(100), field: 'dispositivo' },
  plataforma: { type: DataTypes.STRING(10), field: 'plataforma' },
  ip: { type: DataTypes.INET, field: 'ipcreacion' },
  creadoEn: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW, field: 'fcreacion' },
  expiraEn: { type: DataTypes.DATE, allowNull: false, field: 'fexpira' },
  usadoEn: { type: DataTypes.DATE, field: 'fusado' },
  revocadoEn: { type: DataTypes.DATE, field: 'frevocado' },
  motivoRevocacion: { type: DataTypes.STRING(30), field: 'motivorevocacion' },
}, opcionesSimple('TSESIONES'));

module.exports = Sesion;
