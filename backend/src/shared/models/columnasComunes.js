const { DataTypes } = require('sequelize');

// Ayudas para los modelos de las tablas T (ver database/migraciones/LEEME.md y PATRON_TABLAS_FITBANK.md).
//
// Tablas HISTÓRICAS: llevan FDESDE, FHASTA, VERSIONCONTROL y CUSUARIO_MODIFICACION. Los maneja el trigger de la
// BD (FNVERSION): el backend solo los lee. La fila vigente tiene FHASTA = 2999-12-31.
//   define('Persona', { ...columnasPropias, ...columnasHistorial }, opcionesHistorial('TPERSONAS'))
//
// Tablas SIMPLES (sesiones, códigos, logs): no llevan historial; solo se usa opcionesSimple().

const columnasHistorial = {
  fDesde: { type: DataTypes.DATE, field: 'fdesde' },
  fHasta: { type: DataTypes.DATE, field: 'fhasta' },
  versionControl: { type: DataTypes.INTEGER, field: 'versioncontrol' },
  usuarioModificacion: { type: DataTypes.STRING(30), field: 'cusuario_modificacion' },
};

// 2999-12-31 00:00 hora de Ecuador (UTC-5): la versión vigente de cada registro
const VIGENTE = new Date('2999-12-31T05:00:00.000Z');

// Sin createdAt/updatedAt (la fecha del último cambio es FDESDE, que pone el trigger) y con el filtro de lo
// vigente puesto por defecto: findAll/findByPk nunca traen versiones cerradas del historial.
const opcionesHistorial = (tableName) => ({
  tableName: tableName.toLowerCase(),
  freezeTableName: true,
  timestamps: false,
  defaultScope: { where: { fHasta: VIGENTE } },
});

const opcionesSimple = (tableName) => ({
  tableName: tableName.toLowerCase(),
  freezeTableName: true,
  timestamps: false,
});

module.exports = { columnasHistorial, opcionesHistorial, opcionesSimple, VIGENTE };
