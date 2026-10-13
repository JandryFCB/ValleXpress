const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada } = require('../../shared/models/columnasComunes');
const Usuario = require('../auth/usuario.model');
const Direccion = require('../direcciones/direccion.model');
const HorarioVendedor = require('./horarioVendedor.model');

// Tabla TNEGOCIOS (historial en la misma tabla): el vendedor ES un usuario con rol vendedor y su negocio cuelga de
// CUSUARIO (jcayapa), que en el modelo es "id" (igual a usuarioId). Teléfono y correo del dueño salen de su PERSONA;
// el local es una dirección de la persona tipo LOC (direccionId = CDIRECCION): de ahí salen latitud y longitud.
const Vendedor = sequelize.define('Vendedor', {
  id: { type: DataTypes.STRING(30), primaryKey: true, field: 'cusuario' },          // TUSUARIOSID.CUSUARIO
  usuarioId: {
    type: DataTypes.VIRTUAL(DataTypes.STRING, ['id']),
    get() { return this.getDataValue('id'); },
    set(valor) { this.setDataValue('id', valor); },
  },
  nombreNegocio: {
    type: DataTypes.STRING(200),
    allowNull: false,
    field: 'negocio',
    validate: { notEmpty: { msg: 'El nombre del negocio es requerido' } },
  },
  razonSocial: { type: DataTypes.STRING(200), field: 'razonsocial' },
  ruc: { type: DataTypes.STRING(13), field: 'ruc' },
  descripcion: { type: DataTypes.TEXT, field: 'descripcion' },
  categoria: { type: DataTypes.CHAR(3), field: 'categoria' },              // CATEGORIAS.CODIGO
  logoId: { type: DataTypes.STRING(30), field: 'logo' },                   // ARCHIVOS.ARCHIVO
  bannerId: { type: DataTypes.STRING(30), field: 'banner' },
  direccionId: { type: DataTypes.STRING(30), field: 'cdireccion' },        // TPERSONADIRECCIONES.CDIRECCION (tipo LOC)
  radioCobertura: { type: DataTypes.DECIMAL(6, 2), field: 'radiokm' },
  costoDelivery: { type: DataTypes.DECIMAL(10, 2), field: 'costodelivery' },
  pedidoMinimo: { type: DataTypes.DECIMAL(10, 2), defaultValue: 0, field: 'pedidominimo' },
  tiempoPreparacionPromedio: { type: DataTypes.INTEGER, field: 'tiempoprepmin' },
  abiertoAhora: { type: DataTypes.BOOLEAN, defaultValue: false, field: 'abierto' },
  aceptaPedidos: { type: DataTypes.BOOLEAN, defaultValue: true, field: 'aceptapedidos' },
  comision: { type: DataTypes.DECIMAL(5, 2), field: 'comision' },
  calificacionPromedio: { type: DataTypes.DECIMAL(3, 2), defaultValue: 0, field: 'calificacion' },
  totalCalificaciones: { type: DataTypes.INTEGER, defaultValue: 0, field: 'totalcalif' },
  totalPedidos: { type: DataTypes.INTEGER, defaultValue: 0, field: 'totalpedidos' },
  aprobacion: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'aprobacion' },  // ESTADOAPROBACION.CODIGO
  aprobadoPor: { type: DataTypes.STRING(30), field: 'aprobadopor' },
  aprobadoEn: { type: DataTypes.DATE, field: 'aprobadoen' },
  ...columnasComunes,
}, opcionesVersionada('TNEGOCIOS'));

Vendedor.belongsTo(Usuario, { foreignKey: 'id', as: 'usuario' });
Vendedor.belongsTo(Direccion, { foreignKey: 'direccionId', as: 'local' });
Vendedor.hasMany(HorarioVendedor, { foreignKey: 'vendedorId', as: 'horarios' });

module.exports = Vendedor;
