const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial, opcionesSimple } = require('../../shared/models/columnasComunes');
const { Negocio } = require('../negocios/negocio.model');
const Usuario = require('../auth/usuario.model');
const { Repartidor } = require('../repartidores/repartidor.model');

// Tabla TPEDIDOS (histórica): cada cambio de estado deja su versión; de ahí sale la línea de tiempo del seguimiento.
// El código (CPEDIDO) lo asigna la BD. Los montos y la dirección de entrega se copian al crear el pedido.
const Pedido = sequelize.define('Pedido', {
  id: { type: DataTypes.BIGINT, primaryKey: true, field: 'cpedido', defaultValue: Sequelize.literal('DEFAULT') },
  clienteId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  negocioId: { type: DataTypes.BIGINT, allowNull: false, field: 'cnegocio' },
  repartidorId: { type: DataTypes.STRING(30), field: 'cusuario_repartidor' },
  estado: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'cestatuspedido' },   // TESTATUSPEDIDOID
  metodoPago: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'cmetodopago' },   // TMETODOSPAGOID
  direccionId: { type: DataTypes.BIGINT, field: 'cdireccion' },
  direccionEntrega: { type: DataTypes.STRING(500), allowNull: false, field: 'direccionentrega' },
  referenciaEntrega: { type: DataTypes.STRING(500), field: 'referenciaentrega' },
  latitud: { type: DataTypes.DECIMAL(10, 8), allowNull: false, field: 'latitudentrega' },
  longitud: { type: DataTypes.DECIMAL(11, 8), allowNull: false, field: 'longitudentrega' },
  subtotal: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'subtotal' },
  costoEnvio: { type: DataTypes.DECIMAL(8, 2), allowNull: false, defaultValue: 0, field: 'costoenvio' },
  descuento: { type: DataTypes.DECIMAL(8, 2), allowNull: false, defaultValue: 0, field: 'descuento' },
  propina: { type: DataTypes.DECIMAL(8, 2), allowNull: false, defaultValue: 0, field: 'propina' },
  total: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'total' },
  pagado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'espagado' },
  notas: { type: DataTypes.STRING(300), field: 'notas' },
  tiempoEstimado: { type: DataTypes.SMALLINT, field: 'tiempoestimado' },
  motivoCancelacion: { type: DataTypes.STRING(300), field: 'motivocancelacion' },
  fechaPedido: { type: DataTypes.DATE, field: 'fpedido' },
  ...columnasHistorial,
}, opcionesHistorial('TPEDIDOS'));

// Tabla TPEDIDODETALLES (simple): productos del pedido con el nombre y el precio de ese momento
const Detalle = sequelize.define('PedidoDetalle', {
  pedidoId: { type: DataTypes.BIGINT, primaryKey: true, field: 'cpedido' },
  linea: { type: DataTypes.SMALLINT, primaryKey: true, field: 'numerolinea' },
  productoId: { type: DataTypes.BIGINT, allowNull: false, field: 'cproducto' },
  nombre: { type: DataTypes.STRING(120), allowNull: false, field: 'nombreproducto' },
  precioUnitario: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'preciounitario' },
  cantidad: { type: DataTypes.SMALLINT, allowNull: false, field: 'cantidad' },
  subtotal: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'subtotal' },
  notas: { type: DataTypes.STRING(200), field: 'notas' },
}, opcionesSimple('TPEDIDODETALLES'));

// Tabla TCALIFICACIONES (simple): una por pedido y destino (NEGOCIO | REPARTIDOR)
const Calificacion = sequelize.define('Calificacion', {
  pedidoId: { type: DataTypes.BIGINT, primaryKey: true, field: 'cpedido' },
  destino: { type: DataTypes.STRING(10), primaryKey: true, field: 'destino' },
  autorId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  negocioId: { type: DataTypes.BIGINT, field: 'cnegocio' },
  repartidorId: { type: DataTypes.STRING(30), field: 'cusuario_repartidor' },
  puntuacion: { type: DataTypes.SMALLINT, allowNull: false, field: 'puntuacion' },
  comentario: { type: DataTypes.STRING(500), field: 'comentario' },
  creadoEn: { type: DataTypes.DATE, field: 'fcreacion' },
}, opcionesSimple('TCALIFICACIONES'));

Pedido.hasMany(Detalle, { foreignKey: 'pedidoId', sourceKey: 'id', as: 'detalles' });
Pedido.hasMany(Calificacion, { foreignKey: 'pedidoId', sourceKey: 'id', as: 'calificaciones' });
Pedido.belongsTo(Negocio, { foreignKey: 'negocioId', targetKey: 'id', as: 'negocio' });
Pedido.belongsTo(Usuario, { foreignKey: 'clienteId', targetKey: 'id', as: 'cliente' });
Pedido.belongsTo(Usuario, { foreignKey: 'repartidorId', targetKey: 'id', as: 'repartidor' });
Pedido.belongsTo(Repartidor, { foreignKey: 'repartidorId', targetKey: 'usuarioId', as: 'perfilRepartidor' });
// El dueño del negocio (su teléfono le sirve al repartidor)
if (!Negocio.associations.dueno) Negocio.belongsTo(Usuario, { foreignKey: 'duenoId', targetKey: 'id', as: 'dueno' });

module.exports = { Pedido, Detalle, Calificacion };
