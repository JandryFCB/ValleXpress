const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada, clavePrimaria } = require('../../shared/models/columnasComunes');
const { ESTADOPEDIDO } = require('../../shared/constants/codigos');
const Usuario = require('../auth/usuario.model');
const Vendedor = require('../vendedores/vendedor.model');
const Repartidor = require('../repartidores/repartidor.model');
const Direccion = require('../direcciones/direccion.model');
const DetallePedido = require('../shared/detallePedido.model');

// Tabla TPEDIDOS (historial en la misma tabla). La clave es CPEDIDO (PED-20261006-000001), la asigna la BD; en el modelo es "id".
// El estado vive en el catálogo ESTADOPEDIDO (ver shared/constants/codigos.js). Los atributos conservan los
// nombres que usa la app (clienteId, fechaPedido, costoDelivery...) apuntando a las columnas nuevas.
const Pedido = sequelize.define('Pedido', {
  id: clavePrimaria('cpedido'),
  clienteId: { type: DataTypes.STRING(30), allowNull: false, field: 'cliente' },           // USUARIOS.USUARIO
  vendedorId: { type: DataTypes.STRING(30), allowNull: false, field: 'vendedor' },         // TUSUARIOSID.CUSUARIO (dueño del negocio)
  repartidorId: { type: DataTypes.STRING(30), field: 'repartidor' },                       // TUSUARIOSID.CUSUARIO (repartidor)
  direccionEntregaId: { type: DataTypes.STRING(30), field: 'cdireccion' },                 // TDIRECCIONESID.CDIRECCION
  domicilio: { type: DataTypes.TEXT, field: 'domicilio' },                                 // copia de la dirección al pedir
  latitudEntrega: { type: DataTypes.DECIMAL(10, 8), field: 'latitudentrega' },
  longitudEntrega: { type: DataTypes.DECIMAL(11, 8), field: 'longitudentrega' },
  estado: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: ESTADOPEDIDO.PENDIENTE, field: 'estado' },
  subtotal: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'subtotal' },
  descuento: { type: DataTypes.DECIMAL(10, 2), field: 'descuento' },
  impuestos: { type: DataTypes.DECIMAL(10, 2), field: 'impuestos' },
  costoDelivery: { type: DataTypes.DECIMAL(10, 2), field: 'costodelivery' },
  propina: { type: DataTypes.DECIMAL(10, 2), field: 'propina' },
  comision: { type: DataTypes.DECIMAL(10, 2), field: 'comision' },
  total: { type: DataTypes.DECIMAL(10, 2), allowNull: false, field: 'total' },
  cuponId: { type: DataTypes.STRING(30), field: 'ccupon' },
  metodoPago: { type: DataTypes.CHAR(3), allowNull: false, field: 'metodopago' },          // METODOPAGO.CODIGO
  pagado: { type: DataTypes.BOOLEAN, field: 'pagado' },
  notasCliente: { type: DataTypes.TEXT, field: 'notascliente' },
  notasVendedor: { type: DataTypes.TEXT, field: 'notasvendedor' },
  distanciaKm: { type: DataTypes.DECIMAL(6, 2), field: 'distanciakm' },
  tiempoEstimado: { type: DataTypes.INTEGER, field: 'tiempoestmin' },
  programadoPara: { type: DataTypes.DATE, field: 'programadopara' },
  pinEntrega: { type: DataTypes.STRING(6), field: 'pinentrega' },
  motivoCancel: { type: DataTypes.TEXT, field: 'motivocancel' },
  canceladoPor: { type: DataTypes.STRING(30), field: 'canceladopor' },
  fechaPedido: { type: DataTypes.DATE, field: 'pedidoen' },
  fechaConfirmacion: { type: DataTypes.DATE, field: 'confirmadoen' },
  fechaPreparacion: { type: DataTypes.DATE, field: 'preparacionen' },
  fechaListo: { type: DataTypes.DATE, field: 'listoen' },
  fechaAsignacion: { type: DataTypes.DATE, field: 'asignadoen' },
  fechaRecogida: { type: DataTypes.DATE, field: 'recogidoen' },
  fechaEntrega: { type: DataTypes.DATE, field: 'entregadoen' },
  fechaRecibido: { type: DataTypes.DATE, field: 'recibidoen' },
  fechaCancelado: { type: DataTypes.DATE, field: 'canceladoen' },
  ...columnasComunes,
}, opcionesVersionada('TPEDIDOS'));

Pedido.belongsTo(Usuario, { foreignKey: 'clienteId', as: 'cliente' });
Pedido.belongsTo(Vendedor, { foreignKey: 'vendedorId', as: 'vendedor' });
Pedido.belongsTo(Repartidor, { foreignKey: 'repartidorId', as: 'repartidor' });
Pedido.belongsTo(Direccion, { foreignKey: 'direccionEntregaId', as: 'direccionEntrega' });
Pedido.hasMany(DetallePedido, { foreignKey: 'pedidoId', as: 'detalles' });
DetallePedido.belongsTo(Pedido, { foreignKey: 'pedidoId', as: 'pedido' });

module.exports = Pedido;
