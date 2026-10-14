const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial } = require('../../shared/models/columnasComunes');

// Tabla TPERSONATELEFONOS (histórica, hija de la persona). La PK real es (CPERSONA, STELEFONO, FHASTA).
// STELEFONO (1, 2, 3...) lo asigna la BD dentro de cada persona.
const Telefono = sequelize.define('Telefono', {
  personaId: { type: DataTypes.BIGINT, primaryKey: true, field: 'cpersona' },
  secuencia: { type: DataTypes.SMALLINT, primaryKey: true, field: 'stelefono', defaultValue: Sequelize.literal('DEFAULT') },   // lo asigna el trigger de la BD
  numero: { type: DataTypes.STRING(20), allowNull: false, field: 'numerotelefono' },
  tipo: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'ctipotelefono' },       // TTIPOSTELEFONOID
  principal: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'esprincipal' },
  verificadoEn: { type: DataTypes.DATE, field: 'fverificado' },
  ...columnasHistorial,
}, opcionesHistorial('TPERSONATELEFONOS'));

module.exports = Telefono;
