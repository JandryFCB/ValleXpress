const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');

// Tabla TPERSONATELEFONOS (historial en la misma tabla). La clave es CTELEFONO (1, 2, 3...), la asigna la BD.
// Cuelga de la PERSONA (personaId = CPERSONA). Solo uno por persona es el principal (el que usa la app).
const Telefono = sequelize.define('Telefono', {
  id: { type: DataTypes.INTEGER, primaryKey: true, field: 'ctelefono', defaultValue: Sequelize.literal('DEFAULT') },
  personaId: { type: DataTypes.INTEGER, allowNull: false, field: 'cpersona' },                  // TPERSONASID.CPERSONA
  tipo: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: 'MOV', field: 'ctipotelefono' },   // TTIPOSTELEFONO: MOV, CAS, TRA, WAP
  numero: { type: DataTypes.STRING(20), allowNull: false, field: 'numero' },
  principal: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'principal' },
  verificado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'verificado' },
  verificadoEn: { type: DataTypes.DATE, field: 'verificadoen' },
  ...columnasComunes,
}, opcionesVersionada('TPERSONATELEFONOS'));

module.exports = Telefono;
