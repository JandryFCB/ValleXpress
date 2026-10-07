const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase, clavePrimaria } = require('../../shared/models/columnasComunes');

// Tabla ARCHIVOS: imágenes y documentos. Solo guarda metadatos y rutas; el archivo está en disco (backend/uploads).
// La clave es ARCHIVO (ARC-000001), generada por la BD; en el modelo es "id".
const Archivo = sequelize.define('Archivo', {
  id: clavePrimaria('archivo'),
  propietario: { type: DataTypes.STRING(30), field: 'propietario' },       // USUARIOS.USUARIO que lo subió
  categoria: { type: DataTypes.STRING(20), allowNull: false, field: 'categoria' },
  nombreOriginal: { type: DataTypes.STRING(255), field: 'nombreoriginal' },
  mime: { type: DataTypes.STRING(100), allowNull: false, field: 'mime' },
  extension: { type: DataTypes.STRING(10), field: 'extension' },
  bytes: { type: DataTypes.BIGINT, allowNull: false, field: 'bytes' },
  ancho: { type: DataTypes.INTEGER, field: 'ancho' },
  alto: { type: DataTypes.INTEGER, field: 'alto' },
  hash: { type: DataTypes.CHAR(64), field: 'hash' },
  almacen: { type: DataTypes.STRING(10), allowNull: false, defaultValue: 'LOCAL', field: 'almacen' },
  rutaOriginal: { type: DataTypes.TEXT, allowNull: false, field: 'rutaoriginal' },
  rutaOptimizada: { type: DataTypes.TEXT, field: 'rutaoptimizada' },
  rutaMediana: { type: DataTypes.TEXT, field: 'rutamediana' },
  rutaMiniatura: { type: DataTypes.TEXT, field: 'rutaminiatura' },
  urlPublica: { type: DataTypes.TEXT, field: 'urlpublica' },
  blurhash: { type: DataTypes.STRING(100), field: 'blurhash' },
  optimizado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'optimizado' },
  bytesOptimizado: { type: DataTypes.BIGINT, field: 'bytesoptimizado' },
  ...columnasComunes,
}, opcionesBase('ARCHIVOS'));

module.exports = Archivo;
