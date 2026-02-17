const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');


const DetallePedido = sequelize.define('DetallePedido', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  pedidoId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'pedidos',
      key: 'id'
    },
    field: 'pedido_id'
  },
  productoId: {
    type: DataTypes.UUID,
    references: {
      model: 'productos',
      key: 'id'
    },
    field: 'producto_id'
  },
  cantidad: {
    type: DataTypes.INTEGER,
    allowNull: false,
    validate: {
      min: { args: [1], msg: 'La cantidad debe ser al menos 1' }
    }
  },
  precioUnitario: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
    field: 'precio_unitario'
  },
  subtotal: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false
  },
  notas: {
    type: DataTypes.TEXT
  }
}, {
  tableName: 'detalle_pedidos',
  timestamps: false,
  underscored: true
});

// Las asociaciones se definen en los modelos relacionados para evitar dependencias circulares

module.exports = DetallePedido;
