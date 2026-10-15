const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TDISPOSITIVOS (simple): token de Firebase (FCM) de cada celular, para enviarle notificaciones push.
// Un token pertenece a un solo usuario a la vez (si otro inicia sesión en el mismo celular, se reasigna).
const Dispositivo = sequelize.define('Dispositivo', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'sdispositivo' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  tokenFcm: { type: DataTypes.STRING(255), allowNull: false, field: 'tokenfcm' },
  plataforma: { type: DataTypes.STRING(10), allowNull: false, defaultValue: 'ANDROID', field: 'plataforma' },
  modelo: { type: DataTypes.STRING(100), field: 'modelo' },
  versionApp: { type: DataTypes.STRING(20), field: 'versionapp' },
  activo: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true, field: 'esactivo' },
  creadoEn: { type: DataTypes.DATE, field: 'fcreacion' },
  ultimoUso: { type: DataTypes.DATE, field: 'fultimouso' },
}, opcionesSimple('TDISPOSITIVOS'));

module.exports = Dispositivo;
