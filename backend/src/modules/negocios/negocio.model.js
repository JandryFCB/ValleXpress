const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial, opcionesSimple } = require('../../shared/models/columnasComunes');
const Direccion = require('../direcciones/direccion.model');

// Tabla TNEGOCIOS (histórica): el negocio, con código propio (CNEGOCIO) y su usuario dueño (CUSUARIO).
// Productos y pedidos apuntan al negocio, no al usuario: así un vendedor podría tener más de un local más adelante.
const Negocio = sequelize.define('Negocio', {
  id: { type: DataTypes.BIGINT, primaryKey: true, field: 'cnegocio', defaultValue: Sequelize.literal('DEFAULT') },   // lo asigna la BD
  duenoId: { type: DataTypes.STRING(30), allowNull: false, field: 'cusuario' },
  nombre: { type: DataTypes.STRING(120), allowNull: false, field: 'nombre' },
  descripcion: { type: DataTypes.STRING(500), field: 'descripcion' },
  categoria: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '099', field: 'ccategorianegocio' },
  ruc: { type: DataTypes.STRING(13), field: 'ruc' },
  direccionId: { type: DataTypes.BIGINT, field: 'cdireccion' },             // el local (dirección tipo 005)
  logoId: { type: DataTypes.BIGINT, field: 'carchivo_logo' },
  portadaId: { type: DataTypes.BIGINT, field: 'carchivo_portada' },
  costoEnvio: { type: DataTypes.DECIMAL(8, 2), allowNull: false, defaultValue: 0, field: 'costoenvio' },
  pedidoMinimo: { type: DataTypes.DECIMAL(8, 2), allowNull: false, defaultValue: 0, field: 'pedidominimo' },
  tiempoPreparacion: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 30, field: 'tiempopreparacion' },
  radioKm: { type: DataTypes.DECIMAL(5, 2), allowNull: false, defaultValue: 5, field: 'radiokm' },
  aprobacion: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'cestatusaprobacion' },
  aprobadoEn: { type: DataTypes.DATE, field: 'faprobacion' },
  motivoAprobacion: { type: DataTypes.STRING(300), field: 'motivoaprobacion' },   // por qué se rechazó o suspendió
  ...columnasHistorial,
}, opcionesHistorial('TNEGOCIOS'));

// Tabla TNEGOCIOSESTADO (simple): lo que cambia a cada rato. La fila la crea sola el trigger de TNEGOCIOS.
const NegocioEstado = sequelize.define('NegocioEstado', {
  negocioId: { type: DataTypes.BIGINT, primaryKey: true, field: 'cnegocio' },
  abierto: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'estaabierto' },
  aceptaPedidos: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true, field: 'aceptapedidos' },
  calificacion: { type: DataTypes.DECIMAL(3, 2), allowNull: false, defaultValue: 0, field: 'calificacion' },
  numeroCalificaciones: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0, field: 'numerocalificaciones' },
  numeroPedidos: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0, field: 'numeropedidos' },
  ultimoCambio: { type: DataTypes.DATE, field: 'fultimocambio' },
}, opcionesSimple('TNEGOCIOSESTADO'));

// Tabla TNEGOCIOHORARIOS (histórica, hija del negocio): un registro por día (1 = lunes ... 7 = domingo)
const Horario = sequelize.define('Horario', {
  negocioId: { type: DataTypes.BIGINT, primaryKey: true, field: 'cnegocio' },
  dia: { type: DataTypes.SMALLINT, primaryKey: true, field: 'numerodia' },
  cerrado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'escerrado' },
  apertura: { type: DataTypes.TIME, field: 'horaapertura' },
  cierre: { type: DataTypes.TIME, field: 'horacierre' },
  ...columnasHistorial,
}, opcionesHistorial('TNEGOCIOHORARIOS'));

Negocio.hasOne(NegocioEstado, { foreignKey: 'negocioId', sourceKey: 'id', as: 'estado' });
Negocio.hasMany(Horario, { foreignKey: 'negocioId', sourceKey: 'id', as: 'horarios' });
Negocio.belongsTo(Direccion, { foreignKey: 'direccionId', targetKey: 'id', as: 'local' });

module.exports = { Negocio, NegocioEstado, Horario };
