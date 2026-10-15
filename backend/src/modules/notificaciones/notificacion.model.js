const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TNOTIFICACIONES (simple): avisos que ve cada usuario en la app. El "tipo" es el texto que usa la app
// ('pedido_nuevo', 'pedido_confirmado'...). El código (SNOTIFICACION) lo genera la BD.
const Notificacion = sequelize.define('Notificacion', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'snotificacion' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  tipo: { type: DataTypes.STRING(40), allowNull: false, field: 'tipo' },
  titulo: { type: DataTypes.STRING(150), allowNull: false, field: 'titulo' },
  mensaje: { type: DataTypes.STRING(500), allowNull: false, field: 'mensaje' },
  pedidoId: { type: DataTypes.BIGINT, field: 'cpedido' },
  datos: { type: DataTypes.JSONB, field: 'datos' },
  leida: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'esleida' },
  leidaEn: { type: DataTypes.DATE, field: 'fleida' },
  creadoEn: { type: DataTypes.DATE, field: 'fcreacion' },
}, opcionesSimple('TNOTIFICACIONES'));

module.exports = Notificacion;
