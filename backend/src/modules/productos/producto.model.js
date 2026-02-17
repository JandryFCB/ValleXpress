const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const Vendedor = require('../vendedores/vendedor.model');



const Producto = sequelize.define('Producto', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  vendedorId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'vendedores',
      key: 'id'
    },
    field: 'vendedor_id'
  },
  nombre: {
    type: DataTypes.STRING(200),
    allowNull: false,
    validate: {
      notEmpty: { msg: 'El nombre del producto es requerido' }
    }
  },
  descripcion: {
    type: DataTypes.TEXT
  },
  precio: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
    validate: {
      min: { args: [0], msg: 'El precio debe ser mayor a 0' }
    }
  },
  imagen: {
    type: DataTypes.TEXT
  },
  categoria: {
    type: DataTypes.STRING(50)
  },
  disponible: {
    type: DataTypes.BOOLEAN,
    defaultValue: true
  },
  tiempoPreparacion: {
    type: DataTypes.INTEGER,
    field: 'tiempo_preparacion'
  },
  stock: {
    type: DataTypes.INTEGER,
    defaultValue: 0,
    validate: {
      min: { args: [0], msg: 'El stock no puede ser negativo' }
    }
  }
}, {
  tableName: 'productos',
  timestamps: true,
  underscored: true
});

// Relación con Vendedor
Producto.belongsTo(Vendedor, {
  foreignKey: 'vendedorId',
  as: 'vendedor'
});

Vendedor.hasMany(Producto, {
  foreignKey: 'vendedorId',
  as: 'productos'
});

// Relación con DetallePedido
const DetallePedido = require('../shared/detallePedido.model');



Producto.hasMany(DetallePedido, {
  foreignKey: 'productoId',
  as: 'detalles'
});

DetallePedido.belongsTo(Producto, {
  foreignKey: 'productoId',
  as: 'producto'
});

module.exports = Producto;
