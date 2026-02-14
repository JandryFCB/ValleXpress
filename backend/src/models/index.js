// Carga todos los modelos para que Sequelize los registre antes del sync()

const Usuario = require('./Usuario');
const Direccion = require('./Direccion');
const Vendedor = require('./Vendedor');
const Repartidor = require('./Repartidor');
const Producto = require('./Producto');
const Pedido = require('./Pedido');
const DetallePedido = require('./DetallePedido');
const PasswordResetCode = require('./PasswordResetCode');
const Notificacion = require('./Notificacion');
const EmailVerificationCode = require('./EmailVerificationCode');

module.exports = {
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
