const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial, opcionesSimple } = require('../../shared/models/columnasComunes');
const Usuario = require('../auth/usuario.model');

// Tabla TREPARTIDORES (histórica): perfil del repartidor. La clave es su usuario (CUSUARIO): no tiene código propio.
const Repartidor = sequelize.define('Repartidor', {
  usuarioId: { type: DataTypes.STRING(30), primaryKey: true, field: 'cusuario' },
  vehiculo: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'ctipovehiculo' },   // TTIPOSVEHICULOID
  placa: { type: DataTypes.STRING(10), field: 'placa' },
  color: { type: DataTypes.STRING(30), field: 'colorvehiculo' },
  aprobacion: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'cestatusaprobacion' },
  aprobadoEn: { type: DataTypes.DATE, field: 'faprobacion' },
  motivoAprobacion: { type: DataTypes.STRING(300), field: 'motivoaprobacion' },   // por qué se rechazó o suspendió
  ...columnasHistorial,
}, opcionesHistorial('TREPARTIDORES'));

// Tabla TREPARTIDORESESTADO (simple): en línea, última ubicación, calificación y entregas. La crea el trigger.
const RepartidorEstado = sequelize.define('RepartidorEstado', {
  usuarioId: { type: DataTypes.STRING(30), primaryKey: true, field: 'cusuario' },
  disponible: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'estadisponible' },
  latitud: { type: DataTypes.DECIMAL(10, 8), field: 'latitud' },
  longitud: { type: DataTypes.DECIMAL(11, 8), field: 'longitud' },
  ubicacionEn: { type: DataTypes.DATE, field: 'fubicacion' },
  calificacion: { type: DataTypes.DECIMAL(3, 2), allowNull: false, defaultValue: 0, field: 'calificacion' },
  numeroCalificaciones: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0, field: 'numerocalificaciones' },
  numeroEntregas: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0, field: 'numeroentregas' },
  ultimoCambio: { type: DataTypes.DATE, field: 'fultimocambio' },
}, opcionesSimple('TREPARTIDORESESTADO'));

// Tabla TREPARTIDORUBICACIONES (simple): puntos del recorrido de cada entrega
const Ubicacion = sequelize.define('RepartidorUbicacion', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'subicacion' },
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  pedidoId: { type: DataTypes.BIGINT, allowNull: false, field: 'cpedido' },
  latitud: { type: DataTypes.DECIMAL(10, 8), allowNull: false, field: 'latitud' },
  longitud: { type: DataTypes.DECIMAL(11, 8), allowNull: false, field: 'longitud' },
  precision: { type: DataTypes.DECIMAL(7, 1), field: 'precisionm' },
  velocidadKmh: { type: DataTypes.DECIMAL(5, 1), field: 'velocidadkmh' },
  rumbo: { type: DataTypes.DECIMAL(5, 1), field: 'rumbo' },
  registradoEn: { type: DataTypes.DATE, field: 'fregistro' },
}, opcionesSimple('TREPARTIDORUBICACIONES'));

Repartidor.hasOne(RepartidorEstado, { foreignKey: 'usuarioId', sourceKey: 'usuarioId', as: 'estado' });
Repartidor.belongsTo(Usuario, { foreignKey: 'usuarioId', targetKey: 'id', as: 'usuario' });

module.exports = { Repartidor, RepartidorEstado, Ubicacion };
