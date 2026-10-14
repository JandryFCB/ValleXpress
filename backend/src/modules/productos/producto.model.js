const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial, opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TPRODUCTOS (histórica): los productos de un negocio. Cada cambio (por ejemplo de precio) queda en el
// historial de la misma tabla. El código (CPRODUCTO) lo asigna la BD.
const Producto = sequelize.define('Producto', {
  id: { type: DataTypes.BIGINT, primaryKey: true, field: 'cproducto', defaultValue: Sequelize.literal('DEFAULT') },
  negocioId: { type: DataTypes.BIGINT, allowNull: false, field: 'cnegocio' },
  nombre: { type: DataTypes.STRING(120), allowNull: false, field: 'nombre' },
  descripcion: { type: DataTypes.STRING(500), field: 'descripcion' },
  precio: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'precio' },
  estado: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'cestatusproducto' },  // TESTATUSPRODUCTOID
  seccion: { type: DataTypes.STRING(60), field: 'seccion' },
  imagenId: { type: DataTypes.BIGINT, field: 'carchivo_imagen' },
  orden: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 0, field: 'orden' },
  controlaStock: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'controlastock' },
  ...columnasHistorial,
}, opcionesHistorial('TPRODUCTOS'));

// Tabla TPRODUCTOSINVENTARIO (simple): stock y unidades vendidas. La fila la crea sola el trigger de TPRODUCTOS.
const Inventario = sequelize.define('Inventario', {
  productoId: { type: DataTypes.BIGINT, primaryKey: true, field: 'cproducto' },
  stock: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0, field: 'stock' },
  vendidos: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0, field: 'numerovendidos' },
  ultimoMovimiento: { type: DataTypes.DATE, field: 'fultimomovimiento' },
}, opcionesSimple('TPRODUCTOSINVENTARIO'));

Producto.hasOne(Inventario, { foreignKey: 'productoId', sourceKey: 'id', as: 'inventario' });

module.exports = { Producto, Inventario };
