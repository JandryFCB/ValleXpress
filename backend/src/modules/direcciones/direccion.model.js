const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesVersionada, clavePrimaria } = require('../../shared/models/columnasComunes');

// Tabla TPERSONADIRECCIONES (historial en la misma tabla). La clave es CDIRECCION (DIR-000001), generada por la BD;
// en el modelo es "id". Cuelga de la PERSONA (personaId = CPERSONA), no del usuario.
// "nombre" es el ALIAS de la dirección (Casa, Trabajo) y "direccion" es el texto completo (columna DOMICILIO).
const Direccion = sequelize.define('Direccion', {
  id: clavePrimaria('cdireccion'),
  personaId: { type: DataTypes.INTEGER, allowNull: false, field: 'cpersona' },        // TPERSONAS.CPERSONA
  tipo: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: 'DOM', field: 'ctipodireccion' },   // TTIPOSDIRECCION: DOM, TRA, FAM, OTR, LOC
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
}, opcionesVersionada('TPERSONADIRECCIONES'));

module.exports = Direccion;
