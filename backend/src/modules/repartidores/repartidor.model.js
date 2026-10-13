const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');
const Usuario = require('../auth/usuario.model');

// Tabla TREPARTIDORES (historial en la misma tabla): el repartidor ES un usuario con rol repartidor y su perfil cuelga
// de CUSUARIO (pruiz), que en el modelo es "id" (igual a usuarioId). "foto" es ARCHIVOS (fotoId); la cédula vive en la persona.
const Repartidor = sequelize.define('Repartidor', {
  id: { type: DataTypes.STRING(30), primaryKey: true, field: 'cusuario' },          // TUSUARIOSID.CUSUARIO
  usuarioId: {
    type: DataTypes.VIRTUAL(DataTypes.STRING, ['id']),
    get() { return this.getDataValue('id'); },
    set(valor) { this.setDataValue('id', valor); },
  },
  vehiculo: { type: DataTypes.CHAR(3), field: 'vehiculo' },                // TIPOVEHICULO.CODIGO
  placa: { type: DataTypes.STRING(10), field: 'placa' },
  marca: { type: DataTypes.STRING(50), field: 'marca' },
  modelo: { type: DataTypes.STRING(50), field: 'modelo' },
  color: { type: DataTypes.STRING(30), field: 'color' },
  anio: { type: DataTypes.SMALLINT, field: 'anio' },
  licencia: { type: DataTypes.STRING(30), field: 'licencia' },
  licenciaTipo: { type: DataTypes.STRING(5), field: 'licenciatipo' },
  licenciaVence: { type: DataTypes.DATEONLY, field: 'licenciavence' },
  fotoId: { type: DataTypes.STRING(30), field: 'foto' },                   // ARCHIVOS.ARCHIVO
  disponible: { type: DataTypes.BOOLEAN, defaultValue: false, field: 'disponible' },
  enServicio: { type: DataTypes.BOOLEAN, defaultValue: false, field: 'enservicio' },
  latitud: { type: DataTypes.DECIMAL(10, 8), field: 'latitud' },
  longitud: { type: DataTypes.DECIMAL(11, 8), field: 'longitud' },
  ubicacionEn: { type: DataTypes.DATE, field: 'ubicacionen' },
  calificacionPromedio: { type: DataTypes.DECIMAL(3, 2), defaultValue: 0, field: 'calificacion' },
  totalCalificaciones: { type: DataTypes.INTEGER, defaultValue: 0, field: 'totalcalif' },
  pedidosCompletados: { type: DataTypes.INTEGER, defaultValue: 0, field: 'pedidoscompletos' },
  saldoEfectivo: { type: DataTypes.DECIMAL(10, 2), defaultValue: 0, field: 'saldoefectivo' },
  ganancias: { type: DataTypes.DECIMAL(12, 2), defaultValue: 0, field: 'ganancias' },
  aprobacion: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'aprobacion' },  // ESTADOAPROBACION.CODIGO
  aprobadoPor: { type: DataTypes.STRING(30), field: 'aprobadopor' },
  aprobadoEn: { type: DataTypes.DATE, field: 'aprobadoen' },
  ...columnasComunes,
}, opcionesVersionada('TREPARTIDORES'));

Repartidor.belongsTo(Usuario, { foreignKey: 'id', as: 'usuario' });

module.exports = Repartidor;
