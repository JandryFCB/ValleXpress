const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');
const Usuario = require('./Usuario');

const Vendedor = sequelize.define('Vendedor', {
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
  nombreNegocio: {
    type: DataTypes.STRING(200),
    allowNull: false,
    field: 'nombre_negocio',
    validate: {
      notEmpty: { msg: 'El nombre del negocio es requerido' }
    }
  },
  descripcion: {
    type: DataTypes.TEXT
  },
  logo: {
    type: DataTypes.TEXT
  },
  banner: {
    type: DataTypes.TEXT
  },
  categoria: {
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
  horarioApertura: {
    type: DataTypes.TIME,
    field: 'horario_apertura'
  },
  horarioCierre: {
    type: DataTypes.TIME,
    field: 'horario_cierre'
  },
  diasAtencion: {
    type: DataTypes.STRING(100),
    field: 'dias_atencion'
  },
  tiempoPreparacionPromedio: {
    type: DataTypes.INTEGER,
    field: 'tiempo_preparacion_promedio'
  },
  costoDelivery: {
    type: DataTypes.DECIMAL(10, 2),
    field: 'costo_delivery'
  },
  radioCobertura: {
    type: DataTypes.INTEGER,
    field: 'radio_cobertura'
  },
  abiertoAhora: {
    type: DataTypes.BOOLEAN,
    defaultValue: false,
    field: 'abierto_ahora'
  },
  latitud: {
    type: DataTypes.DECIMAL(10, 8),
    allowNull: true
  },
  longitud: {
    type: DataTypes.DECIMAL(11, 8),
    allowNull: true
  }
}, {

  tableName: 'vendedores',
  timestamps: true,
  underscored: true
});

// Relación con Usuario
Vendedor.belongsTo(Usuario, { 
  foreignKey: 'usuarioId',
  as: 'usuario' 
});

module.exports = Vendedor;
