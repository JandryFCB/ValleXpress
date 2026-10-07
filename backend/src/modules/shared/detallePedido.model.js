const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase } = require('../../shared/models/columnasComunes');
const Producto = require('../productos/producto.model');

// Tabla DETALLEPEDIDO: una fila por producto del pedido. Clave: ID numérico (1, 2, 3). Guarda una COPIA del nombre
// y del precio al momento de la compra (si el vendedor cambia el precio después, el pedido no cambia).
const DetallePedido = sequelize.define('DetallePedido', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'id' },
  pedidoId: { type: DataTypes.STRING(30), allowNull: false, field: 'pedido' },          // PEDIDOS.PEDIDO
  productoId: { type: DataTypes.STRING(30), allowNull: false, field: 'producto' },      // PRODUCTOS.PRODUCTO
  nombre: { type: DataTypes.STRING(200), allowNull: false, field: 'nombre' },
  cantidad: { type: DataTypes.INTEGER, allowNull: false, field: 'cantidad' },
  precioUnitario: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'precio' },
  descuento: { type: DataTypes.DECIMAL(10, 2), field: 'descuento' },
  impuesto: { type: DataTypes.DECIMAL(10, 2), field: 'impuesto' },
  subtotal: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'subtotal' },
  notas: { type: DataTypes.TEXT, field: 'notas' },
  ...columnasComunes,
}, opcionesBase('DETALLEPEDIDO'));

DetallePedido.belongsTo(Producto, { foreignKey: 'productoId', as: 'producto' });

module.exports = DetallePedido;
