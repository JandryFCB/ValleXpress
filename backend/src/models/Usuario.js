const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');
const bcrypt = require('bcryptjs');

const Usuario = sequelize.define('Usuario', {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true
  },
  nombre: {
    type: DataTypes.STRING(100),
    allowNull: false,
    validate: {
      notEmpty: { msg: 'El nombre es requerido' },
      len: { args: [2, 100], msg: 'El nombre debe tener entre 2 y 100 caracteres' }
    }
  },
  apellido: {
    type: DataTypes.STRING(100),
    allowNull: false,
    validate: {
      notEmpty: { msg: 'El apellido es requerido' }
    }
  },
  email: {
    type: DataTypes.STRING(150),
    allowNull: false,
    unique: { msg: 'Este email ya está registrado' },
    validate: {
      isEmail: { msg: 'Debe ser un email válido' }
    }
  },
  telefono: {
    type: DataTypes.STRING(20),
    validate: {
      is: { args: /^[0-9+\-\s()]+$/, msg: 'Teléfono inválido' }
    }
  },

  cedula: {
    type: DataTypes.STRING(10),
    allowNull: false,
    unique: { msg: 'Esta cédula ya está registrada' },
    validate: {
      notEmpty: { msg: 'La cédula es requerida' },
      len: { args: [10, 10], msg: 'La cédula debe tener 10 dígitos' }
    }
  },
  
  passwordHash: {
    type: DataTypes.STRING(255),
    allowNull: false,
    field: 'password_hash'
  },
  tipoUsuario: {
    type: DataTypes.ENUM('cliente', 'vendedor', 'repartidor'),
    allowNull: false,
    field: 'tipo_usuario'
  },
  fotoPerfil: {
    type: DataTypes.TEXT,
    field: 'foto_perfil'
  },
  activo: {
    type: DataTypes.BOOLEAN,
    defaultValue: true
  },
  verificado: {
    type: DataTypes.BOOLEAN,
    defaultValue: false
  },
  fechaRegistro: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
    field: 'fecha_registro'
  },
  ultimaConexion: {
    type: DataTypes.DATE,
    field: 'ultima_conexion'
  }
}, {
  tableName: 'usuarios',
  timestamps: true,
  underscored: true,
  indexes: [
    { fields: ['email'] },
    { fields: ['tipo_usuario'] }
  ]
});

// Hook: Encriptar password antes de crear
Usuario.beforeCreate(async (usuario) => {
  if (usuario.passwordHash) {
    usuario.passwordHash = await bcrypt.hash(usuario.passwordHash, 10);
  }
});

// Hook: Encriptar password antes de actualizar
Usuario.beforeUpdate(async (usuario) => {
  if (usuario.changed('passwordHash')) {
    usuario.passwordHash = await bcrypt.hash(usuario.passwordHash, 10);
  }
});

// Método para verificar password
Usuario.prototype.verificarPassword = async function(password) {
  return await bcrypt.compare(password, this.passwordHash);
};

// Ocultar password en JSON
Usuario.prototype.toJSON = function() {
  const values = { ...this.get() };
  delete values.passwordHash;
  return values;
};

module.exports = Usuario;