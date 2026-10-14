const { DataTypes, Sequelize } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasHistorial, opcionesHistorial } = require('../../shared/models/columnasComunes');

// Tabla TPERSONADIRECCIONES (histórica): direcciones de la persona con su ubicación. La PK real es (CDIRECCION, FHASTA);
// en el modelo basta el código porque el filtro por defecto solo deja ver la fila vigente. El código lo asigna la BD.
const Direccion = sequelize.define('Direccion', {
  id: { type: DataTypes.BIGINT, primaryKey: true, field: 'cdireccion', defaultValue: Sequelize.literal('DEFAULT') },
  personaId: { type: DataTypes.BIGINT, allowNull: false, field: 'cpersona' },
  tipo: { type: DataTypes.CHAR(3), allowNull: false, defaultValue: '001', field: 'ctipodireccion' },   // TTIPOSDIRECCIONID
  nombre: { type: DataTypes.STRING(50), field: 'nombre' },
  direccion: { type: DataTypes.STRING(500), allowNull: false, field: 'direccion' },
  referencia: { type: DataTypes.STRING(500), field: 'referencia' },
  instrucciones: { type: DataTypes.STRING(500), field: 'instrucciones' },
  latitud: { type: DataTypes.DECIMAL(10, 8), allowNull: false, field: 'latitud' },
  longitud: { type: DataTypes.DECIMAL(11, 8), allowNull: false, field: 'longitud' },
  esPredeterminada: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'espredeterminada' },
  ...columnasHistorial,
}, opcionesHistorial('TPERSONADIRECCIONES'));

module.exports = Direccion;
