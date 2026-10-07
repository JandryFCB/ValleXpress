const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase } = require('../../shared/models/columnasComunes');

// Tabla DISPOSITIVOS: tokens de Firebase (FCM) de los celulares de cada usuario, para enviarle notificaciones push.
const Dispositivo = sequelize.define('Dispositivo', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'id' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },
  tokenFcm: { type: DataTypes.TEXT, allowNull: false, field: 'tokenfcm' },
  plataforma: { type: DataTypes.STRING(10), allowNull: false, field: 'plataforma' },       // ANDROID | IOS | WEB
  modelo: { type: DataTypes.STRING(100), field: 'modelo' },
  sistemaVer: { type: DataTypes.STRING(30), field: 'sistemaver' },
  appVer: { type: DataTypes.STRING(20), field: 'appver' },
  ultimoUsoEn: { type: DataTypes.DATE, field: 'ultimousoen' },
  ...columnasComunes,
}, opcionesBase('DISPOSITIVOS'));

module.exports = Dispositivo;
