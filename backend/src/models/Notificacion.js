const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

const Notificacion = sequelize.define('Notificacion', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  usuarioId: {
    type: DataTypes.UUID,
    allowNull: true,
    field: 'usuario_id',
  },
  titulo: {
    type: DataTypes.STRING(200),
    allowNull: false,
  },
  mensaje: {
    type: DataTypes.TEXT,
    allowNull: false,
  },
  tipo: {
    type: DataTypes.STRING(50),
    allowNull: true,
  },
  leida: {
    type: DataTypes.BOOLEAN,
    allowNull: true,
    defaultValue: false,
  },
  pedidoId: {
    type: DataTypes.UUID,
    allowNull: true,
    field: 'pedido_id',
  },
}, {
  tableName: 'notificaciones',
  timestamps: true,
  underscored: true,
  updatedAt: false, // La tabla no tiene columna updated_at
});


module.exports = Notificacion;
