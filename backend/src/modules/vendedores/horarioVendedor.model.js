const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase } = require('../../shared/models/columnasComunes');

// Tabla HORARIOVENDEDOR: un registro por día de la semana (1 = lunes ... 7 = domingo). Clave: ID numérico.
const HorarioVendedor = sequelize.define('HorarioVendedor', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'id' },
  vendedorId: { type: DataTypes.STRING(30), allowNull: false, field: 'vendedor' },    // VENDEDORES.VENDEDOR
  dia: { type: DataTypes.SMALLINT, allowNull: false, field: 'dia' },
  apertura: { type: DataTypes.TIME, field: 'apertura' },
  cierre: { type: DataTypes.TIME, field: 'cierre' },
  cerrado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'cerrado' },
  ...columnasComunes,
}, opcionesBase('HORARIOVENDEDOR'));

module.exports = HorarioVendedor;
