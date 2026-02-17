// Carga todos los modelos para que Sequelize los registre antes del sync()
const { sequelize } = require('./config/database');

const Usuario = require('./modules/auth/usuario.model');
const Direccion = require('./modules/direcciones/direccion.model');
const Vendedor = require('./modules/vendedores/vendedor.model');
const Repartidor = require('./modules/repartidores/repartidor.model');
const Producto = require('./modules/productos/producto.model');
const Pedido = require('./modules/pedidos/pedido.model');
const DetallePedido = require('./modules/shared/detallePedido.model');
const PasswordResetCode = require('./modules/auth/passwordResetCode.model');
const Notificacion = require('./modules/notificaciones/notificacion.model');
const EmailVerificationCode = require('./modules/auth/emailVerificationCode.model');




module.exports = {
  sequelize,
  Usuario,
  Direccion,
  Vendedor,
  Repartidor,
  Producto,
  Pedido,
  DetallePedido,
  PasswordResetCode,
  Notificacion,
  EmailVerificationCode,
};
