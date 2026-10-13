const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial } = require('../../shared/models/columnasComunes');

// Tabla TUSUARIOS (histórica): la cuenta de acceso (rol, estatus, clave). Se usa para ESCRIBIR; para leer al usuario
// completo se usa el modelo Usuario (vista VUSUARIOS). El CUSUARIO (jcayapa) lo genera la BD a partir del nombre
// de la persona y no cambia nunca.
const UsuarioCuenta = sequelize.define('UsuarioCuenta', {
  id: { type: DataTypes.STRING(30), primaryKey: true, field: 'cusuario', defaultValue: Sequelize.literal('DEFAULT') },   // lo asigna el trigger de la BD
  personaId: { type: DataTypes.BIGINT, allowNull: false, field: 'cpersona' },
  rol: { type: DataTypes.CHAR(3), allowNull: false, field: 'crol' },                          // TROLESID
  estatus: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'cestatususuario' },
  claveHash: { type: DataTypes.STRING(255), allowNull: false, field: 'clavehash' },
  claveCambiadaEn: { type: DataTypes.DATE, field: 'fclavecambio' },
  terminosEn: { type: DataTypes.DATE, field: 'fterminos' },
  terminosVer: { type: DataTypes.STRING(20), field: 'versionterminos' },
  ...columnasHistorial,
}, opcionesHistorial('TUSUARIOS'));

module.exports = UsuarioCuenta;
