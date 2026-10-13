const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial } = require('../../shared/models/columnasComunes');

// Tabla TPERSONAS (histórica): los datos de la persona. La PK real es (CPERSONA, FHASTA); en el modelo basta CPERSONA
// porque el filtro por defecto solo deja ver la fila vigente. El código lo asigna la BD (secuencia desde el 2).
const Persona = sequelize.define('Persona', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true, field: 'cpersona' },
  tipoDoc: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'ctipodocumento' },   // TTIPOSDOCUMENTOID
  numeroDoc: { type: DataTypes.STRING(20), allowNull: false, field: 'numerodocumento' },
  nombres: { type: DataTypes.STRING(100), allowNull: false, field: 'nombres' },
  apellidos: { type: DataTypes.STRING(100), allowNull: false, field: 'apellidos' },
  correo: { type: DataTypes.STRING(150), allowNull: false, field: 'correo' },
  correoVerificadoEn: { type: DataTypes.DATE, field: 'fcorreoverificado' },
  nacimiento: { type: DataTypes.DATEONLY, field: 'fnacimiento' },
  ...columnasHistorial,
}, opcionesHistorial('TPERSONAS'));

module.exports = Persona;
