const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');

// Tabla THORARIOSNEGOCIO (historial en la misma tabla): una fila por día de la semana (1 = lunes ... 7 = domingo).
// La clave es CHORARIO (número que asigna la BD); cuelga del vendedor por su CUSUARIO.
const HorarioVendedor = sequelize.define('HorarioVendedor', {
  id: { type: DataTypes.INTEGER, primaryKey: true, field: 'chorario', defaultValue: Sequelize.literal('DEFAULT') },
  vendedorId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },    // TNEGOCIOS.CUSUARIO
  dia: { type: DataTypes.SMALLINT, allowNull: false, field: 'dia' },
  apertura: { type: DataTypes.TIME, field: 'apertura' },
  cierre: { type: DataTypes.TIME, field: 'cierre' },
  cerrado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'cerrado' },
  ...columnasComunes,
}, opcionesVersionada('THORARIOSNEGOCIO'));

module.exports = HorarioVendedor;
