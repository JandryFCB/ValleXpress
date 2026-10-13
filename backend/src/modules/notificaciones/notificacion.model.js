const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');

// Tabla TNOTIFICACIONES (historial en la misma tabla; leída/enviada no crean versión). Clave: CNOTIFICACION (1, 2, 3). El "tipo" conserva los textos que usa la app
// ('pedido_nuevo', 'pedido_listo', 'pedido_en_camino'...).
const Notificacion = sequelize.define('Notificacion', {
  id: { type: DataTypes.INTEGER, primaryKey: true, field: 'cnotificacion', defaultValue: Sequelize.literal('DEFAULT') },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },          // USUARIOS.USUARIO
  tipo: { type: DataTypes.STRING(50), allowNull: false, field: 'tipo' },
  titulo: { type: DataTypes.STRING(200), allowNull: false, field: 'titulo' },
  mensaje: { type: DataTypes.TEXT, allowNull: false, field: 'mensaje' },
  pedidoId: { type: DataTypes.STRING(30), field: 'cpedido' },                             // TPEDIDOSID.CPEDIDO
  datos: { type: DataTypes.JSONB, field: 'datos' },
  canal: { type: DataTypes.STRING(10), field: 'canal' },
  prioridad: { type: DataTypes.STRING(10), field: 'prioridad' },
  leida: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'leida' },
  leidaEn: { type: DataTypes.DATE, field: 'leidaen' },
  enviadaEn: { type: DataTypes.DATE, field: 'enviadaen' },
  errorEnvio: { type: DataTypes.TEXT, field: 'errorenvio' },
  ...columnasComunes,
}, opcionesVersionada('TNOTIFICACIONES'));

module.exports = Notificacion;
