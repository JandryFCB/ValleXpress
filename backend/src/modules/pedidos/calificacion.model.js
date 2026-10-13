const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada, clavePrimaria } = require('../../shared/models/columnasComunes');

// Tabla TCALIFICACIONES (historial en la misma tabla). La clave es CCALIFICACION (CAL-000001). Un cliente califica una vez al vendedor y una vez
// al repartidor de cada pedido (UNIQUE pedido + tipo).
const Calificacion = sequelize.define('Calificacion', {
  id: clavePrimaria('ccalificacion'),
  pedidoId: { type: DataTypes.STRING(30), allowNull: false, field: 'cpedido' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },          // quien califica
  tipo: { type: DataTypes.STRING(12), allowNull: false, field: 'tipo' },                  // VENDEDOR | REPARTIDOR
  vendedorId: { type: DataTypes.STRING(30), field: 'vendedor' },
  repartidorId: { type: DataTypes.STRING(30), field: 'repartidor' },
  puntuacion: { type: DataTypes.DECIMAL(2, 1), allowNull: false, field: 'puntuacion' },
  comentario: { type: DataTypes.TEXT, field: 'comentario' },
  visible: { type: DataTypes.BOOLEAN, field: 'visible' },
  ...columnasComunes,
}, opcionesVersionada('TCALIFICACIONES'));

module.exports = Calificacion;
