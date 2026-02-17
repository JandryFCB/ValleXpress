const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');


const Direccion = sequelize.define('Direccion', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  usuarioId: {
    type: DataTypes.UUID,
    allowNull: false,
    field: 'usuario_id',
  },
  nombre: {
    type: DataTypes.STRING(50),
    allowNull: true,
  },
  direccion: {
    type: DataTypes.TEXT,
    allowNull: false,
  },
  latitud: {
    type: DataTypes.DECIMAL(10, 8),
    allowNull: false,
  },
  longitud: {
    type: DataTypes.DECIMAL(11, 8),
    allowNull: false,
  },
  esPredeterminada: {
    type: DataTypes.BOOLEAN,
    defaultValue: false,
    field: 'es_predeterminada',
  },
}, {
  tableName: 'direcciones',
  timestamps: true,
  underscored: true,
  indexes: [
    { fields: ['usuario_id'] },
  ],
});

// Asociaciones
try {
  const Usuario = require('../auth/usuario.model');


  Direccion.belongsTo(Usuario, { foreignKey: 'usuarioId', as: 'usuario' });
  // Nota: definimos la relación inversa sin requerir aquí para evitar ciclos
  if (Usuario && typeof Usuario.hasMany === 'function') {
    Usuario.hasMany(Direccion, { foreignKey: 'usuarioId', as: 'direcciones' });
  }
} catch (e) {
  // Evitar fallo por require cíclico durante carga inicial; index.js cargará todos.
}

module.exports = Direccion;
