const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

const Pedido = sequelize.define('Pedido', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  numeroPedido: {
    type: DataTypes.STRING(20),
    unique: true,
    field: 'numero_pedido',
    defaultValue: () => {
      const timestamp = Date.now().toString().slice(-8);
      const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
      return `PED-${timestamp}-${random}`;
    }
  },
  clienteId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'usuarios',
      key: 'id'
    },
    field: 'cliente_id'
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
  repartidorId: {
    type: DataTypes.UUID,
    references: {
      model: 'repartidores',
      key: 'id'
    },
    field: 'repartidor_id'
  },
  direccionEntregaId: {
    type: DataTypes.UUID,
    references: {
      model: 'direcciones',
      key: 'id'
    },
    field: 'direccion_entrega_id'
  },
  estado: {
    type: DataTypes.STRING(50),
    allowNull: false,
    defaultValue: 'pendiente',
      validate: {
        isIn: [[
          'pendiente',
          'confirmado',
          'preparando',
          'listo',
          'recogido',
          'en_camino',
          'entregado',
          'recibido_cliente',
          'cancelado'
        ]]
      }

  },

  subtotal: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false
  },
  costoDelivery: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
    field: 'costo_delivery'
  },
  total: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false
  },
  metodoPago: {
    type: DataTypes.STRING(50),
    field: 'metodo_pago'
  },
  pagado: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  paypalOrderId: {
    type: DataTypes.STRING(100),
    field: 'paypal_order_id'
  },
  notasCliente: {
    type: DataTypes.TEXT,
    field: 'notas_cliente'
  },
  tiempoEstimado: {
    type: DataTypes.INTEGER,
    field: 'tiempo_estimado'
  },
  fechaPedido: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
    field: 'fecha_pedido'
  },
  fechaConfirmacion: {
    type: DataTypes.DATE,
    field: 'fecha_confirmacion'
  },
  fechaPreparacion: {
    type: DataTypes.DATE,
    field: 'fecha_preparacion'
  },
  fechaListo: {
    type: DataTypes.DATE,
    field: 'fecha_listo'
  },
  fechaRecogida: {
    type: DataTypes.DATE,
    field: 'fecha_recogida'
  },
  fechaEntrega: {
    type: DataTypes.DATE,
    field: 'fecha_entrega'
  }
}, {
  tableName: 'pedidos',
  timestamps: true,
  underscored: true
});

// Importar modelos para asociaciones
const Usuario = require('./Usuario');
const Vendedor = require('./Vendedor');
const Repartidor = require('./Repartidor');
const DetallePedido = require('./DetallePedido');
const Direccion = require('./Direccion');

// Asociaciones
Pedido.belongsTo(Usuario, {
  foreignKey: 'clienteId',
  as: 'cliente'
});

Pedido.belongsTo(Vendedor, {
  foreignKey: 'vendedorId',
  as: 'vendedor'
});

Pedido.belongsTo(Repartidor, {
  foreignKey: 'repartidorId',
  as: 'repartidor'
});

Pedido.belongsTo(Direccion, {
  foreignKey: 'direccionEntregaId',
  as: 'direccionEntrega'
});

Pedido.hasMany(DetallePedido, {
  foreignKey: 'pedidoId',
  as: 'detalles'
});

DetallePedido.belongsTo(Pedido, {
  foreignKey: 'pedidoId',
  as: 'pedido'
});

module.exports = Pedido;
