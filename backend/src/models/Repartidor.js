const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');
const Usuario = require('./Usuario');

const Repartidor = sequelize.define('Repartidor', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  usuarioId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'usuarios',
      key: 'id'
    },
    field: 'usuario_id'
  },
  vehiculo: {
    type: DataTypes.STRING(50)
  },
  placa: {
    type: DataTypes.STRING(10),
    allowNull: false,
    unique: { msg: 'Esta placa ya está registrada' },
    validate: {
      notEmpty: { msg: 'La placa es requerida' },
      len: { args: [5, 10], msg: 'La placa debe tener entre 5 y 10 caracteres' }
    }
  },

  licencia: {
    type: DataTypes.STRING(50)
  },
  calificacionPromedio: {
    type: DataTypes.DECIMAL(3, 2),
    defaultValue: 0.00,
    field: 'calificacion_promedio'
  },
  totalCalificaciones: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    field: 'total_calificaciones'
  },
  disponible: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  latitud: {
    type: DataTypes.DECIMAL(10, 8),
    field: 'latitud'
  },
  longitud: {
    type: DataTypes.DECIMAL(11, 8),
    field: 'longitud'
  },
  pedidosCompletados: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    field: 'pedidos_completados'
  },
  foto: {
    type: DataTypes.TEXT,
    allowNull: true
  },
  cedula: {
    type: DataTypes.STRING(10),
    field: 'cedula'
  }
}, {
  tableName: 'repartidores',
  timestamps: true,
  underscored: true
});

// Relación con Usuario
Repartidor.belongsTo(Usuario, {
  foreignKey: 'usuarioId',
  as: 'usuario'
});

module.exports = Repartidor;
