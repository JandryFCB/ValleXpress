// Carga todos los modelos para que Sequelize los registre
const { sequelize } = require('./config/database');

const Usuario = require('./modules/auth/usuario.model');
const CodigoVerificacion = require('./modules/auth/codigoVerificacion.model');
const Direccion = require('./modules/direcciones/direccion.model');
const Archivo = require('./modules/archivos/archivo.model');
const Vendedor = require('./modules/vendedores/vendedor.model');
const HorarioVendedor = require('./modules/vendedores/horarioVendedor.model');
const Repartidor = require('./modules/repartidores/repartidor.model');
const Producto = require('./modules/productos/producto.model');
const Pedido = require('./modules/pedidos/pedido.model');
const DetallePedido = require('./modules/shared/detallePedido.model');
const Notificacion = require('./modules/notificaciones/notificacion.model');
const Dispositivo = require('./modules/notificaciones/dispositivo.model');
const Calificacion = require('./modules/pedidos/calificacion.model');

module.exports = {
  sequelize,
  Usuario,
  CodigoVerificacion,
  Direccion,
  Archivo,
  Vendedor,
  HorarioVendedor,
  Repartidor,
  Producto,
  Pedido,
  DetallePedido,
  Notificacion,
  Dispositivo,
  Calificacion,
};
