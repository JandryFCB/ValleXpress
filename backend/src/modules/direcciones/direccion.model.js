const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase, clavePrimaria } = require('../../shared/models/columnasComunes');
const Usuario = require('../auth/usuario.model');

// Tabla DIRECCIONES. La clave es DIRECCION (DIR-000001), generada por la BD; en el modelo es "id".
// "nombre" es el ALIAS de la dirección (Casa, Trabajo) y "direccion" es el texto completo (columna DOMICILIO).
const Direccion = sequelize.define('Direccion', {
  id: clavePrimaria('direccion'),
  usuarioId: { type: DataTypes.STRING(30), allowNull: false, field: 'usuario' },     // USUARIOS.USUARIO
  nombre: { type: DataTypes.STRING(50), field: 'alias' },
  callePrincipal: { type: DataTypes.STRING(150), field: 'calleprincipal' },
  calleSecundaria: { type: DataTypes.STRING(150), field: 'callesecundaria' },
  numeracion: { type: DataTypes.STRING(20), field: 'numeracion' },
  sector: { type: DataTypes.STRING(100), field: 'sector' },
  ciudad: { type: DataTypes.STRING(100), field: 'ciudad' },
  provincia: { type: DataTypes.STRING(100), field: 'provincia' },
  codigoPostal: { type: DataTypes.STRING(10), field: 'codigopostal' },
  direccion: { type: DataTypes.TEXT, allowNull: false, field: 'domicilio' },
  referencia: { type: DataTypes.TEXT, field: 'referencia' },
  instrucciones: { type: DataTypes.TEXT, field: 'instrucciones' },
  telContacto: { type: DataTypes.STRING(20), field: 'telcontacto' },
  latitud: { type: DataTypes.DECIMAL(10, 8), allowNull: false, field: 'latitud' },
  longitud: { type: DataTypes.DECIMAL(11, 8), allowNull: false, field: 'longitud' },
  esPredeterminada: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'espredeterminada' },
  ...columnasComunes,
}, opcionesBase('DIRECCIONES'));

Direccion.belongsTo(Usuario, { foreignKey: 'usuarioId', as: 'usuario' });

module.exports = Direccion;
