const Usuario = require('./usuario.model');
const Persona = require('./persona.model');
const UsuarioCuenta = require('./usuarioCuenta.model');
const UsuarioAcceso = require('./usuarioAcceso.model');
const Telefono = require('../telefonos/telefono.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const TokenService = require('../../shared/services/token.service');
const SesionService = require('../../shared/services/sesion.service');
const CodigoService = require('../../shared/services/codigo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { logMensaje, auditar } = require('../../shared/services/log.service');
const { hashClave, compararClave, HASHRELLENO } = require('../../shared/utils/clave');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');
const { ROLES, APIAROL, ROLESREGISTRABLES, PROPOSITOCODIGO } = require('../../shared/constants/codigos');

// Toda la lógica de negocio de autenticación. El controller solo llama a estos métodos.
//
// Sesión persistente: el login y el registro devuelven un token de ACCESO corto (15 min, campo "token") y un
// REFRESH TOKEN largo (campo "refreshToken") que la app guarda cifrado y canjea en POST /auth/refresh.

const MAXINTENTOSFALLIDOS = 5;       // tras 5 claves incorrectas seguidas...
const MINUTOSBLOQUEO = 15;           // ...la cuenta se bloquea 15 minutos
const TIPODOCCEDULA = '001';         // TTIPOSDOCUMENTO: 001 cédula
const ipDe = (req) => (req?.ip ? String(req.ip).replace(/^::ffff:/, '') : null);

// Lo que se devuelve del usuario a la app (nunca el hash de la clave)
const usuarioPublico = (u) => ({
  id: u.id,
  usuario: u.id,                 // jcayapa: clave y nombre para iniciar sesión
  nombre: u.nombre,
  apellido: u.apellido,
  email: u.email,
  telefono: u.telefono,
  cedula: u.cedula,
  tipoUsuario: u.tipoUsuario,
  activo: u.activo,
  verificado: u.verificado,
});

// Perfil completo. fotoPerfil queda en null hasta que exista el módulo de archivos.
const usuarioPerfil = (u) => ({
  ...usuarioPublico(u),
  fotoPerfil: null,
  createdAt: u.creadoEn,
  ultimaConexion: u.ultimaConexion,
});

// Abre una sesión persistente para el usuario y arma el par de tokens que recibe la app
async function abrirSesion(usuario, req, opciones = {}) {
  const refreshToken = await SesionService.crear(
    usuario.id,
    { dispositivo: req?.body?.dispositivo, plataforma: req?.body?.plataforma, ip: ipDe(req) },
    opciones,
  );
  return { token: TokenService.crear(usuario), refreshToken, expiresIn: TokenService.segundosAcceso() };
}

// Envía un correo con código. Devuelve true/false; si falla lo deja en TLOGMENSAJES (no rompe la petición).
// Solo en desarrollo el código se imprime en consola (para probar sin proveedor de correo).
async function enviarCorreoCodigo(tipo, { email, codigo, nombre }, req) {
  const mailer = require('../../services/mailer.service');
  try {
    if (tipo === 'reset') await mailer.sendPasswordResetCode(email, codigo);
    else await mailer.sendEmailVerificationCode(email, codigo, nombre);
    return true;
  } catch (e) {
    logMensaje({ nivel: 'ADVERTENCIA', modulo: 'CORREO', accion: 'ENVIOFALLIDO', mensaje: `No se pudo enviar el correo (${tipo})`, detalle: { error: e.message, tipo }, req });
    if (process.env.NODE_ENV === 'development') console.log(`[DEV] Código de ${tipo} para ${email}: ${codigo}`);
    return false;
  }
}

// ---------------------------------------------------------------------------------------------
// Registro
// ---------------------------------------------------------------------------------------------
// Crea la persona, la cuenta (el CUSUARIO lo genera la BD a partir del nombre) y el teléfono principal.
// El perfil de negocio (vendedor) o de reparto (repartidor) se completa en sus propios módulos.
async function registrar(datos, req) {
  const tipo = datos.tipoUsuario || 'cliente';
  if (!ROLESREGISTRABLES.includes(tipo)) throw AppError.badRequest('Tipo de usuario inválido', 'TIPOUSUARIOINVALIDO');

  const email = normalizarEmail(datos.email);
  const telefono = normalizarTelefono(datos.telefono);
  const terminosVer = String(await ConfiguracionService.obtener('VERSIONTERMINOS', '1.0'));
  const claveHash = await hashClave(datos.password);
  const ahora = new Date();

  const cuenta = await withTransaction(async (t) => {
    // 1) El email debe haberse verificado (la app ya lo exige; ahora también el servidor)
    const verificacion = await CodigoService.exigirEmailVerificado(email, { transaction: t });

    // 2) Datos únicos entre las personas vigentes
    if (await Persona.findOne({ where: { correo: email }, transaction: t })) throw AppError.conflict('El email ya está registrado', 'EMAILDUPLICADO');
    if (await Persona.findOne({ where: { tipoDoc: TIPODOCCEDULA, numeroDoc: datos.cedula }, transaction: t })) throw AppError.conflict('La cédula ya está registrada', 'CEDULADUPLICADA');
    if (await Telefono.findOne({ where: { numero: telefono }, transaction: t })) throw AppError.conflict('El teléfono ya está registrado', 'TELEFONODUPLICADO');

    // 3) Persona -> cuenta -> teléfono (la BD asigna CPERSONA desde el 2 y genera el CUSUARIO)
    const persona = await Persona.create({
      tipoDoc: TIPODOCCEDULA,
      numeroDoc: datos.cedula,
      nombres: datos.nombre.trim(),
      apellidos: datos.apellido.trim(),
      correo: email,
      correoVerificadoEn: verificacion.verificadoEn || ahora,
    }, { transaction: t });

    const nueva = await UsuarioCuenta.create({
      personaId: persona.id,
      rol: APIAROL[tipo],
      claveHash,
      terminosEn: ahora,
      terminosVer,
    }, { transaction: t });

    await Telefono.create({ personaId: persona.id, numero: telefono, principal: true }, { transaction: t });

    // 4) El código de verificación queda consumido (no sirve para registrar otra cuenta)
    await CodigoService.consumir(verificacion, { transaction: t });
    return nueva;
  });

  const usuario = await Usuario.findByPk(cuenta.id);
  auditar({ usuarioId: usuario.id, accion: 'REGISTRO', entidad: 'USUARIOS', entidadId: usuario.id, detalle: { tipoUsuario: tipo }, req });
  return { usuario: usuarioPublico(usuario), ...(await abrirSesion(usuario, req)) };
}

// ---------------------------------------------------------------------------------------------
// Login (con bloqueo temporal por intentos fallidos)
// ---------------------------------------------------------------------------------------------
// "email" puede traer el correo o el usuario (jcayapa): si lleva @ es un correo
async function login({ email: identificador, password }, req) {
  const id = normalizarEmail(identificador);
  const usuario = await Usuario.findOne({ where: id.includes('@') ? { email: id } : { id } });

  if (!usuario) {
    await compararClave(password, HASHRELLENO);     // mismo tiempo de respuesta exista o no la cuenta
    throw AppError.unauthorized('Credenciales inválidas', 'CREDENCIALESINVALIDAS');
  }
  if (!usuario.activo) throw AppError.forbidden('Cuenta desactivada', 'CUENTADESACTIVADA');

  if (usuario.bloqueadoHasta && new Date(usuario.bloqueadoHasta) > new Date()) {
    const segundos = Math.ceil((new Date(usuario.bloqueadoHasta) - new Date()) / 1000);
    throw AppError.tooMany(
      `Cuenta bloqueada temporalmente por demasiados intentos fallidos. Intenta en ${Math.ceil(segundos / 60)} minutos`,
      'CUENTABLOQUEADA',
      { retryAfter: segundos },
    );
  }

  if (!(await usuario.verificarClave(password))) {
    const intentos = usuario.intentosFallidos + 1;
    const bloquear = intentos >= MAXINTENTOSFALLIDOS;
    await UsuarioAcceso.update({
      intentos: bloquear ? 0 : intentos,
      bloqueadoHasta: bloquear ? new Date(Date.now() + MINUTOSBLOQUEO * 60 * 1000) : null,
    }, { where: { id: usuario.id } });
    auditar({ usuarioId: usuario.id, accion: 'LOGINFALLIDO', entidad: 'USUARIOS', entidadId: usuario.id, detalle: { intentos, bloqueado: bloquear }, req });
    throw AppError.unauthorized('Credenciales inválidas', 'CREDENCIALESINVALIDAS');
  }

  await UsuarioAcceso.update({ intentos: 0, bloqueadoHasta: null, ultimaConexion: new Date(), ultimaIp: ipDe(req) }, { where: { id: usuario.id } });
  auditar({ usuarioId: usuario.id, accion: 'LOGIN', entidad: 'USUARIOS', entidadId: usuario.id, req });
  return { usuario: usuarioPublico(usuario), ...(await abrirSesion(usuario, req)) };
}

// ---------------------------------------------------------------------------------------------
// Sesión persistente: renovar y cerrar
// ---------------------------------------------------------------------------------------------
// Canjea el refresh token por un token de acceso nuevo y un refresh token nuevo (rotación).
async function refrescar({ refreshToken }, req) {
  const { usuario, refreshToken: nuevo } = await SesionService.rotar(refreshToken, ipDe(req));
  await UsuarioAcceso.update({ ultimaConexion: new Date(), ultimaIp: ipDe(req) }, { where: { id: usuario.id } });
  return { usuario: usuarioPublico(usuario), token: TokenService.crear(usuario), refreshToken: nuevo, expiresIn: TokenService.segundosAcceso() };
}

// Cierra la sesión de este equipo
async function cerrarSesion({ refreshToken }, req) {
  await SesionService.cerrar(refreshToken);
  auditar({ accion: 'LOGOUT', entidad: 'USUARIOS', req });
}

// Cierra la sesión en todos los equipos del usuario
async function cerrarTodasLasSesiones(usuarioId, req) {
  const cerradas = await SesionService.cerrarTodas(usuarioId, 'CIERRETODAS');
  auditar({ usuarioId, accion: 'LOGOUTTODAS', entidad: 'USUARIOS', entidadId: usuarioId, detalle: { cerradas }, req });
  return { cerradas };
}

// ---------------------------------------------------------------------------------------------
// Perfil
// ---------------------------------------------------------------------------------------------
async function cargarUsuario(id) {
  const usuario = await Usuario.findByPk(id);
  if (!usuario) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return usuario;
}

async function obtenerPerfil(id) {
  return usuarioPerfil(await cargarUsuario(id));
}

// Pendiente: la foto de perfil se guarda en el módulo de archivos (aún no migrado a las tablas nuevas)
async function subirFoto() {
  throw new AppError('La foto de perfil estará disponible pronto', 501, 'NOIMPLEMENTADO');
}

async function actualizarPerfil(id, { nombre, apellido, telefono }, req) {
  const usuario = await cargarUsuario(id);

  if (telefono && telefono !== usuario.telefono) {
    const existente = await Telefono.findOne({ where: { numero: telefono } });
    if (existente && String(existente.personaId) !== String(usuario.personaId)) {
      throw AppError.conflict('El teléfono ya está registrado', 'TELEFONODUPLICADO');
    }
  }

  await withTransaction(async (t) => {
    if (nombre || apellido) {
      await Persona.update({
        ...(nombre && { nombres: nombre.trim() }),
        ...(apellido && { apellidos: apellido.trim() }),
      }, { where: { id: usuario.personaId }, transaction: t });
    }
    if (telefono && telefono !== usuario.telefono) {
      const principal = await Telefono.findOne({ where: { personaId: usuario.personaId, principal: true }, transaction: t });
      if (principal) await Telefono.update({ numero: telefono }, { where: { personaId: usuario.personaId, secuencia: principal.secuencia }, transaction: t });
      else await Telefono.create({ personaId: usuario.personaId, numero: telefono, principal: true }, { transaction: t });
    }
  }, { usuarioId: id });

  auditar({ usuarioId: id, accion: 'PERFILACTUALIZADO', entidad: 'USUARIOS', entidadId: id, req });
  return usuarioPerfil(await cargarUsuario(id));
}

// Cambia la clave, cierra las sesiones de TODOS los equipos y deja abierta una sesión nueva en este
// (así quien cambia su clave no queda fuera, pero un ladrón con una sesión vieja sí).
async function cambiarClave(id, { passwordActual, passwordNueva }, req) {
  const usuario = await cargarUsuario(id);
  if (!(await usuario.verificarClave(passwordActual))) {
    throw AppError.unauthorized('Contraseña actual incorrecta', 'CLAVEACTUALINCORRECTA');
  }
  const claveHash = await hashClave(passwordNueva);
  const sesion = await withTransaction(async (t) => {
    await UsuarioCuenta.update({ claveHash, claveCambiadaEn: new Date() }, { where: { id }, transaction: t });
    await SesionService.cerrarTodas(id, 'CLAVE', { transaction: t });
    return abrirSesion(usuario, req, { transaction: t });
  }, { usuarioId: id });
  auditar({ usuarioId: id, accion: 'CAMBIOCLAVE', entidad: 'USUARIOS', entidadId: id, req });
  return sesion;
}

// ---------------------------------------------------------------------------------------------
// Recuperar contraseña: 1) pedir código  2) verificarlo  3) fijar la clave nueva
// ---------------------------------------------------------------------------------------------
const MENSAJERESET = 'Si el correo existe, te enviamos un código de verificación.';

async function solicitarCodigoReset(emailEntrada, req) {
  const email = normalizarEmail(emailEntrada);
  const usuario = await Usuario.findOne({ where: { email } });

  // Se genera igual exista o no la cuenta (así la respuesta no revela si el correo está registrado)
  const { codigo } = await CodigoService.generar({
    proposito: PROPOSITOCODIGO.RESETCLAVE, email, usuarioId: usuario?.id ?? null, ip: ipDe(req), minutosExpira: 10,
  });

  // El correo solo se envía a cuentas reales y sin esperar la respuesta del proveedor
  // (esperarla haría la petición más lenta cuando el correo existe, y delataría la cuenta).
  if (usuario) enviarCorreoCodigo('reset', { email, codigo }, req);
  return { message: MENSAJERESET };
}

async function verificarCodigoReset({ email: emailEntrada, code }) {
  const email = normalizarEmail(emailEntrada);
  const registro = await CodigoService.verificar({ proposito: PROPOSITOCODIGO.RESETCLAVE, email, codigo: code });
  const usuario = registro.usuarioId ? await Usuario.findByPk(registro.usuarioId) : null;
  if (!usuario) throw AppError.badRequest('Código inválido o expirado', 'CODIGOINVALIDO');

  await CodigoService.consumir(registro);
  return { resetToken: TokenService.crearReset(usuario) };
}

async function restablecerClave({ resetToken, newPassword }, req) {
  const payload = TokenService.verificarReset(resetToken);
  const usuario = await Usuario.findOne({ where: { id: payload.userId, email: payload.email } });
  if (!usuario) throw AppError.unauthorized('Token inválido', 'TOKENRESETINVALIDO');

  // Token de un solo uso: si la clave ya cambió desde que se emitió, deja de servir
  const cambioActual = usuario.claveCambiadaEn ? new Date(usuario.claveCambiadaEn).getTime() : 0;
  if (cambioActual !== (payload.cc || 0)) throw AppError.unauthorized('Este enlace ya fue utilizado', 'TOKENRESETUSADO');

  const claveHash = await hashClave(newPassword);
  await withTransaction(async (t) => {
    await UsuarioCuenta.update({ claveHash, claveCambiadaEn: new Date() }, { where: { id: usuario.id }, transaction: t });
    await UsuarioAcceso.update({ intentos: 0, bloqueadoHasta: null }, { where: { id: usuario.id }, transaction: t });
    await SesionService.cerrarTodas(usuario.id, 'CLAVE', { transaction: t });     // las sesiones viejas dejan de servir
  }, { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'RESETCLAVE', entidad: 'USUARIOS', entidadId: usuario.id, req });
}

// ---------------------------------------------------------------------------------------------
// Verificación de email (antes de registrarse)
// ---------------------------------------------------------------------------------------------
async function enviarCodigoEmail({ email: emailEntrada, nombre, fcmToken }, req) {
  const email = normalizarEmail(emailEntrada);

  // No se envían códigos a cuentas que ya existen (evita spam a usuarios registrados)
  if (await Persona.findOne({ where: { correo: email } })) {
    throw AppError.conflict('El email ya está registrado', 'EMAILDUPLICADO');
  }

  const { codigo } = await CodigoService.generar({
    proposito: PROPOSITOCODIGO.EMAIL, email, ip: ipDe(req), tokenFcm: fcmToken || null, minutosExpira: 15,
  });

  const enviado = await enviarCorreoCodigo('verificacion', { email, codigo, nombre: nombre || 'Usuario' }, req);
  if (!enviado && process.env.NODE_ENV === 'production') {
    throw new AppError('No se pudo enviar el correo de verificación. Intenta más tarde.', 502, 'CORREONOENVIADO');
  }

  if (fcmToken) {
    try {
      await require('../../services/fcm.service').sendVerificationCodeNotification(fcmToken, codigo);
    } catch (e) {
      logMensaje({ nivel: 'ADVERTENCIA', modulo: 'FCM', accion: 'PUSHFALLIDO', mensaje: 'No se pudo enviar el código por notificación push', detalle: { error: e.message }, req });
    }
  }
  return { message: 'Código de verificación enviado' };
}

async function verificarCodigoEmail({ email: emailEntrada, code }) {
  await CodigoService.verificar({ proposito: PROPOSITOCODIGO.EMAIL, email: normalizarEmail(emailEntrada), codigo: code });
  return { message: 'Email verificado correctamente', verified: true };
}

// ---------------------------------------------------------------------------------------------
// Consultas en tiempo real del formulario de registro
// ---------------------------------------------------------------------------------------------
const existeCedula = async (cedula) => (await Persona.count({ where: { tipoDoc: TIPODOCCEDULA, numeroDoc: cedula } })) > 0;
const existeEmail = async (email) => (await Persona.count({ where: { correo: normalizarEmail(email) } })) > 0;

module.exports = {
  ROLES,
  registrar, login, refrescar, cerrarSesion, cerrarTodasLasSesiones,
  obtenerPerfil, actualizarPerfil, subirFoto, cambiarClave,
  solicitarCodigoReset, verificarCodigoReset, restablecerClave,
  enviarCodigoEmail, verificarCodigoEmail,
  existeCedula, existeEmail,
};
