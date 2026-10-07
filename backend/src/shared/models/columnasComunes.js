const { DataTypes, Sequelize } = require('sequelize');

// Columnas que lleva TODA tabla versionada (ver database/schema.sql). Se mezclan en cada modelo:
//   define('Usuario', { ...columnasPropias, ...columnasComunes }, opcionesBase('USUARIOS'))
//
// Las columnas en la BD se guardan en minúsculas (usuario, nombres...). FDESDE / FHASTA / VERSIONCONTROL
// las maneja el trigger de la BD: el backend solo las lee.
const columnasComunes = {
  activo: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true, field: 'activo' },
  fDesde: { type: DataTypes.DATE, field: 'fdesde' },
  fHasta: { type: DataTypes.DATE, field: 'fhasta' },
  versionControl: { type: DataTypes.INTEGER, field: 'versioncontrol' },
  datosExtra: { type: DataTypes.STRING(250), allowNull: true, field: 'datosextra' },
  creadoEn: { type: DataTypes.DATE, field: 'creadoen' },
  creadoPor: { type: DataTypes.STRING(30), allowNull: true, field: 'creadopor' },        // USUARIOS.USUARIO
  actualizadoPor: { type: DataTypes.STRING(30), allowNull: true, field: 'actualizadopor' },
  eliminadoEn: { type: DataTypes.DATE, allowNull: true, field: 'eliminadoen' },
};

// Opciones comunes: nombre exacto de tabla (minúsculas, como la guarda PostgreSQL), borrado lógico con
// ELIMINADOEN y sin updatedAt (la fecha de la última modificación es FDESDE, que pone el trigger).
const opcionesBase = (tableName) => ({
  tableName: tableName.toLowerCase(),
  freezeTableName: true,
  timestamps: true,
  createdAt: 'creadoEn',
  updatedAt: false,
  deletedAt: 'eliminadoEn',
  paranoid: true,
});

// Clave primaria legible (VEN-000001, jcayapa...). La genera la BASE DE DATOS al insertar
// (valor por defecto o trigger), así que el backend no la envía: se lee del resultado del create().
// En el modelo el atributo se llama siempre "id" para que findByPk() y el resto de código funcionen igual.
const clavePrimaria = (columna, largo = 30) => ({
  type: DataTypes.STRING(largo),
  primaryKey: true,
  field: columna,
  defaultValue: Sequelize.literal('DEFAULT'),
});

module.exports = { columnasComunes, opcionesBase, clavePrimaria };
