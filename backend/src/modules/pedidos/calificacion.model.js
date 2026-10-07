const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase, clavePrimaria } = require('../../shared/models/columnasComunes');

// Tabla CALIFICACIONES. La clave es CALIFICACION (CAL-000001). Un cliente califica una vez al vendedor y una vez
// al repartidor de cada pedido (UNIQUE pedido + tipo).
const Calificacion = sequelize.define('Calificacion', {
  id: clavePrimaria('calificacion'),
  pedidoId: { type: DataTypes.STRING(30), allowNull: false, field: 'pedido' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },          // quien califica
  tipo: { type: DataTypes.STRING(12), allowNull: false, field: 'tipo' },                  // VENDEDOR | REPARTIDOR
  vendedorId: { type: DataTypes.STRING(30), field: 'vendedor' },
  repartidorId: { type: DataTypes.STRING(30), field: 'repartidor' },
  puntuacion: { type: DataTypes.DECIMAL(2, 1), allowNull: false, field: 'puntuacion' },
  comentario: { type: DataTypes.TEXT, field: 'comentario' },
  visible: { type: DataTypes.BOOLEAN, field: 'visible' },
  ...columnasComunes,
}, opcionesBase('CALIFICACIONES'));

module.exports = Calificacion;
