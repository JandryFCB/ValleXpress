const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada, clavePrimaria } = require('../../shared/models/columnasComunes');
const { ESTADOPRODUCTO } = require('../../shared/constants/codigos');
const Vendedor = require('../vendedores/vendedor.model');

// Tabla TPRODUCTOS (historial en la misma tabla). La clave es CPRODUCTO (PRO-000001), la asigna la BD; en el modelo es "id".
// El estado vive en el catálogo ESTADOPRODUCTO (001 disponible, 002 agotado, 003 no disponible, 004 descontinuado).
const Producto = sequelize.define('Producto', {
  id: clavePrimaria('cproducto'),
  vendedorId: { type: DataTypes.STRING(30), allowNull: false, field: 'vendedor' },    // TUSUARIOSID.CUSUARIO (dueño del negocio)
  categoria: { type: DataTypes.CHAR(3), field: 'categoria' },                          // CATEGORIAS.CODIGO
  estado: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: ESTADOPRODUCTO.DISPONIBLE, field: 'estado' },
  nombre: { type: DataTypes.STRING(200), allowNull: false, field: 'nombre' },
  descripcion: { type: DataTypes.TEXT, field: 'descripcion' },
  sku: { type: DataTypes.STRING(50), field: 'sku' },
  precio: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'precio' },
  precioAnterior: { type: DataTypes.DECIMAL(10, 2), field: 'precioanterior' },
  costo: { type: DataTypes.DECIMAL(10, 2), field: 'costo' },
  iva: { type: DataTypes.DECIMAL(5, 2), field: 'iva' },
  imagenId: { type: DataTypes.STRING(30), field: 'imagen' },                           // ARCHIVOS.ARCHIVO
  controlaStock: { type: DataTypes.BOOLEAN, field: 'controlastock' },
  stock: { type: DataTypes.INTEGER, field: 'stock' },
  stockMinimo: { type: DataTypes.INTEGER, field: 'stockminimo' },
  tiempoPreparacion: { type: DataTypes.INTEGER, field: 'tiempoprepmin' },
  destacado: { type: DataTypes.BOOLEAN, field: 'destacado' },
  etiquetas: { type: DataTypes.ARRAY(DataTypes.TEXT), field: 'etiquetas' },
  orden: { type: DataTypes.INTEGER, field: 'orden' },
  totalVendidos: { type: DataTypes.INTEGER, field: 'totalvendidos' },

  // Compatibilidad con la API: "disponible" (true/false) = el estado es 001. No es una columna.
  disponible: {
    type: DataTypes.VIRTUAL(DataTypes.BOOLEAN, ['estado']),
    get() { return this.getDataValue('estado') === ESTADOPRODUCTO.DISPONIBLE; },
    set(valor) { this.setDataValue('estado', valor ? ESTADOPRODUCTO.DISPONIBLE : ESTADOPRODUCTO.NODISPONIBLE); },
  },
  ...columnasComunes,
}, opcionesVersionada('TPRODUCTOS'));

Producto.belongsTo(Vendedor, { foreignKey: 'vendedorId', as: 'vendedor' });
Vendedor.hasMany(Producto, { foreignKey: 'vendedorId', as: 'productos' });

module.exports = Producto;
