const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { opcionesSimple } = require('../../shared/models/columnasComunes');

// Tabla TUSUARIOSACCESO (simple, sin historial): lo que cambia en cada login. Una fila por usuario; la crea sola
// el trigger de TUSUARIOS.
const UsuarioAcceso = sequelize.define('UsuarioAcceso', {
  id: { type: DataTypes.STRING(30), primaryKey: true, field: 'cusuario' },
  intentos: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 0, field: 'numerointentos' },
  bloqueadoHasta: { type: DataTypes.DATE, field: 'fbloqueadohasta' },
  ultimaConexion: { type: DataTypes.DATE, field: 'fultimaconexion' },
  ultimaIp: { type: DataTypes.INET, field: 'ipultimaconexion' },
}, opcionesSimple('TUSUARIOSACCESO'));

module.exports = UsuarioAcceso;
