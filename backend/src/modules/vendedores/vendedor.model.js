const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase, clavePrimaria } = require('../../shared/models/columnasComunes');
const Usuario = require('../auth/usuario.model');
const HorarioVendedor = require('./horarioVendedor.model');

// Tabla VENDEDORES. La clave primaria es VENDEDOR (VEN-000001), generada por la BD; en el modelo es "id".
// Se conservan los nombres de atributos que usan los módulos aún no migrados.
// PENDIENTE al migrar el módulo de vendedores: logo/banner (ahora son ARCHIVOS: logoId, bannerId) y los
// horarios (ahora son la tabla HORARIOVENDEDOR), que ya no son columnas de esta tabla.
const Vendedor = sequelize.define('Vendedor', {
  id: clavePrimaria('vendedor'),
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },   // USUARIOS.USUARIO
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
  telefonoNegocio: { type: DataTypes.STRING(20), field: 'telefono' },
  emailNegocio: { type: DataTypes.STRING(150), field: 'email' },
  direccionNegocio: { type: DataTypes.TEXT, field: 'domicilio' },
  latitud: { type: DataTypes.DECIMAL(10, 8), field: 'latitud' },
  longitud: { type: DataTypes.DECIMAL(11, 8), field: 'longitud' },
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
}, opcionesBase('VENDEDORES'));

Vendedor.belongsTo(Usuario, { foreignKey: 'usuarioId', as: 'usuario' });
Vendedor.hasMany(HorarioVendedor, { foreignKey: 'vendedorId', as: 'horarios' });

module.exports = Vendedor;
