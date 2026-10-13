const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');
const Producto = require('../productos/producto.model');

// Tabla TPEDIDODETALLE (historial en la misma tabla): una fila por producto del pedido. Clave: CDETALLE (1, 2, 3). Guarda una COPIA del nombre
// y del precio al momento de la compra (si el vendedor cambia el precio después, el pedido no cambia).
const DetallePedido = sequelize.define('DetallePedido', {
  id: { type: DataTypes.INTEGER, primaryKey: true, field: 'cdetalle', defaultValue: Sequelize.literal('DEFAULT') },
  pedidoId: { type: DataTypes.STRING(30), allowNull: false, field: 'cpedido' },         // TPEDIDOSID.CPEDIDO
  productoId: { type: DataTypes.STRING(30), allowNull: false, field: 'cproducto' },     // TPRODUCTOSID.CPRODUCTO
  nombre: { type: DataTypes.STRING(200), allowNull: false, field: 'nombre' },
  cantidad: { type: DataTypes.INTEGER, allowNull: false, field: 'cantidad' },
  precioUnitario: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'precio' },
  descuento: { type: DataTypes.DECIMAL(10, 2), field: 'descuento' },
  impuesto: { type: DataTypes.DECIMAL(10, 2), field: 'impuesto' },
  subtotal: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'subtotal' },
  notas: { type: DataTypes.TEXT, field: 'notas' },
  ...columnasComunes,
}, opcionesVersionada('TPEDIDODETALLE'));

DetallePedido.belongsTo(Producto, { foreignKey: 'productoId', as: 'producto' });

module.exports = DetallePedido;
