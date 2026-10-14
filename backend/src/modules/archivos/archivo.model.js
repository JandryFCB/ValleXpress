const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TARCHIVOS (simple): imágenes optimizadas. No se editan: una imagen nueva es otra fila.
// El código (CARCHIVO) lo genera la BD.
const Archivo = sequelize.define('Archivo', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'carchivo' },
  usuarioId: { type: DataTypes.STRING(30), field: 'cusuario' },
  categoria: { type: DataTypes.STRING(12), allowNull: false, field: 'categoria' },
  nombreOriginal: { type: DataTypes.STRING(255), field: 'nombreoriginal' },
  mime: { type: DataTypes.STRING(50), allowNull: false, defaultValue: 'image/webp', field: 'mime' },
  bytes: { type: DataTypes.INTEGER, allowNull: false, field: 'bytes' },
  ancho: { type: DataTypes.INTEGER, field: 'ancho' },
  alto: { type: DataTypes.INTEGER, field: 'alto' },
  hash: { type: DataTypes.CHAR(64), allowNull: false, field: 'hash' },
  ruta: { type: DataTypes.STRING(200), allowNull: false, field: 'ruta' },
  rutaMediana: { type: DataTypes.STRING(200), allowNull: false, field: 'rutamediana' },
  rutaMiniatura: { type: DataTypes.STRING(200), allowNull: false, field: 'rutaminiatura' },
  creadoEn: { type: DataTypes.DATE, field: 'fcreacion' },
}, opcionesSimple('TARCHIVOS'));

module.exports = Archivo;
