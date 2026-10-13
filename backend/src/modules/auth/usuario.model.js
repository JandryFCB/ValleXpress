const { DataTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { columnasComunes, opcionesBase, clavePrimaria } = require('../../shared/models/columnasComunes');
const { ROLAAPI, APIAROL } = require('../../shared/constants/codigos');
const { normalizarEmail } = require('../../shared/utils/normalizers');
const { compararClave } = require('../../shared/utils/clave');

// Vista VUSUARIOS (usuario + persona + teléfono principal + foto, solo lo vigente). Se puede leer y escribir:
// los triggers de la BD reparten los datos en TPERSONAS, TUSUARIOS, TPERSONATELEFONOS y TPERSONAIMAGENES, y el historial
// queda en cada tabla (FDESDE/FHASTA). La clave es el USUARIO (jcayapa): lo genera la BD a partir del nombre y NO se puede
// cambiar nunca. En el modelo se llama "id" (así findByPk, req.usuario.id y el JWT siguen funcionando).
// Los demás atributos conservan sus nombres (nombre, apellido, cedula, tipoUsuario...) para que los módulos
// que aún no se migraron compilen; cada uno apunta a la columna nueva.
const Usuario = sequelize.define('Usuario', {
  id: clavePrimaria('usuario'),
  personaId: { type: DataTypes.INTEGER, field: 'cpersona' },               // TPERSONAS.CPERSONA (la BD lo asigna; solo lectura)
  rol: { type: DataTypes.CHAR(3), allowNull: false, field: 'rol' },        // ROLES.CODIGO
  nombre: { type: DataTypes.STRING(100), allowNull: false, field: 'nombres' },
  apellido: { type: DataTypes.STRING(100), allowNull: false, field: 'apellidos' },
  email: {
    type: DataTypes.STRING(150),
    allowNull: false,
    field: 'email',
    set(valor) { this.setDataValue('email', normalizarEmail(valor)); },    // siempre en minúsculas
  },
  telefono: { type: DataTypes.STRING(20), field: 'telefono' },
  tipoDoc: { type: DataTypes.STRING(10), allowNull: false, defaultValue: 'CEDULA', field: 'tipodoc' },
  cedula: { type: DataTypes.STRING(20), allowNull: false, field: 'numdoc' },
  fechaNac: { type: DataTypes.DATEONLY, field: 'fechanac' },
  genero: { type: DataTypes.STRING(10), field: 'genero' },
  passwordHash: { type: DataTypes.STRING(255), allowNull: false, field: 'clavehash' },
  fotoId: { type: DataTypes.STRING(30), field: 'foto' },                   // ARCHIVOS.ARCHIVO
  verificado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'emailverif' },
  emailVerificadoEn: { type: DataTypes.DATE, field: 'emailverifen' },
  telVerificado: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'telverif' },
  telVerificadoEn: { type: DataTypes.DATE, field: 'telverifen' },
  terminosEn: { type: DataTypes.DATE, field: 'terminosen' },
  terminosVer: { type: DataTypes.STRING(20), field: 'terminosver' },
  idioma: { type: DataTypes.STRING(5), allowNull: false, defaultValue: 'es', field: 'idioma' },
  zonaHoraria: { type: DataTypes.STRING(50), allowNull: false, defaultValue: 'America/Guayaquil', field: 'zonahoraria' },
  aceptaNotif: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true, field: 'aceptanotif' },
  aceptaPromo: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false, field: 'aceptapromo' },
  intentosFallidos: { type: DataTypes.SMALLINT, allowNull: false, defaultValue: 0, field: 'intentosfallidos' },
  bloqueadoHasta: { type: DataTypes.DATE, field: 'bloqueadohasta' },
  claveCambiadaEn: { type: DataTypes.DATE, field: 'clavecambiadaen' },
  ultimaConexion: { type: DataTypes.DATE, field: 'ultimaconexion' },
  ultimaIp: { type: DataTypes.INET, field: 'ultimaip' },

  // El mismo valor que "id", con el nombre que usa la API y la app: "usuario" (jcayapa). No es una columna.
  usuario: {
    type: DataTypes.VIRTUAL(DataTypes.STRING, ['id']),
    get() { return this.getDataValue('id'); },
  },

  // Compatibilidad con la API actual: 'cliente' | 'vendedor' | 'repartidor' | 'administrador'
  // (se calcula desde rol; no es una columna). Los módulos viejos siguen usando req.usuario.tipoUsuario.
  tipoUsuario: {
    type: DataTypes.VIRTUAL(DataTypes.STRING, ['rol']),
    get() { return ROLAAPI[this.getDataValue('rol')]; },
    set(valor) { this.setDataValue('rol', APIAROL[valor]); },
  },

  ...columnasComunes,
}, opcionesBase('VUSUARIOS'));

Usuario.prototype.verificarClave = function verificarClave(clave) {
  return compararClave(clave, this.passwordHash);
};
Usuario.prototype.verificarPassword = Usuario.prototype.verificarClave;   // nombre antiguo

// Nunca devolver el hash de la clave
Usuario.prototype.toJSON = function toJSON() {
  const valores = { ...this.get() };
  delete valores.passwordHash;
  return valores;
};

module.exports = Usuario;
