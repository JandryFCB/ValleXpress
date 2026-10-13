const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');

// Tabla TDISPOSITIVOS (historial en la misma tabla; la clave CDISPOSITIVO la asigna la BD): tokens de Firebase (FCM) de los celulares de cada usuario, para enviarle notificaciones push.
const Dispositivo = sequelize.define('Dispositivo', {
  id: { type: DataTypes.INTEGER, primaryKey: true, field: 'cdispositivo', defaultValue: Sequelize.literal('DEFAULT') },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },
  tokenFcm: { type: DataTypes.TEXT, allowNull: false, field: 'tokenfcm' },
  plataforma: { type: DataTypes.STRING(10), allowNull: false, field: 'plataforma' },       // ANDROID | IOS | WEB
  modelo: { type: DataTypes.STRING(100), field: 'modelo' },
  sistemaVer: { type: DataTypes.STRING(30), field: 'sistemaver' },
  appVer: { type: DataTypes.STRING(20), field: 'appver' },
  ultimoUsoEn: { type: DataTypes.DATE, field: 'ultimousoen' },
  ...columnasComunes,
}, opcionesVersionada('TDISPOSITIVOS'));

module.exports = Dispositivo;
