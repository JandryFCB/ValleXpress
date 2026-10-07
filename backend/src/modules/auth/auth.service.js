const Usuario = require('./usuario.model');
const VendedorService = require('../vendedores/vendedor.service');
const RepartidorService = require('../repartidores/repartidor.service');
const ArchivoService = require('../../shared/services/archivo.service');
const Repartidor = require('../repartidores/repartidor.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const TokenService = require('../../shared/services/token.service');
const CodigoService = require('../../shared/services/codigo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { logMensaje, auditar } = require('../../shared/services/log.service');
const { hashClave, compararClave, HASHRELLENO } = require('../../shared/utils/clave');
const { normalizarEmail, normalizarTelefono, normalizarPlaca } = require('../../shared/utils/normalizers');
const {
  ROLES, APIAROL, ROLESREGISTRABLES, PROPOSITOCODIGO,
} = require('../../shared/constants/codigos');

// Toda la lógica de negocio de autenticación. El controller solo llama a estos métodos.

const MAXINTENTOSFALLIDOS = 5;       // tras 5 claves incorrectas seguidas...
const MINUTOSBLOQUEO = 15;           // ...la cuenta se bloquea 15 minutos
const ipDe = (req) => (req?.ip ? String(req.ip).replace(/^::ffff:/, '') : null);

// Lo que se devuelve del usuario a la app (nunca el hash de la clave)
const usuarioPublico = (u) => ({
  id: u.id,
  usuario: u.id,                 // jcayapa: clave primaria y nombre para iniciar sesión
  nombre: u.nombre,
  apellido: u.apellido,
  email: u.email,
  telefono: u.telefono,
  cedula: u.cedula,
  tipoUsuario: u.tipoUsuario,
  activo: u.activo,
  verificado: u.verificado,
});

// Perfil completo. fotoPerfil es la URL de la imagen (guardada en ARCHIVOS) o null.
const usuarioPerfil = (u, fotoPerfil = null) => ({
  ...usuarioPublico(u),
  fotoPerfil,
  createdAt: u.creadoEn,
  ultimaConexion: u.ultimaConexion,
});

// Envía un correo con código. Devuelve true/false; si falla lo deja en LOGMENSAJES (no rompe la petición).
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
async function registrar(datos, req) {
  const tipo = datos.tipoUsuario || 'cliente';
  if (!ROLESREGISTRABLES.includes(tipo)) throw AppError.badRequest('Tipo de usuario inválido', 'TIPOUSUARIOINVALIDO');

  const email = normalizarEmail(datos.email);
  const telefono = normalizarTelefono(datos.telefono);
  const placa = tipo === 'repartidor' ? normalizarPlaca(datos.placa) : null;
  const nombre = datos.nombre.trim();

  const terminosVer = await ConfiguracionService.obtener('VERSIONTERMINOS', '1.0');
  const claveHash = await hashClave(datos.password);
  const ahora = new Date();

  const usuario = await withTransaction(async (t) => {
    // 1) El email debe haberse verificado (la app ya lo exige; ahora también el servidor)
    const verificacion = await CodigoService.exigirEmailVerificado(email, { transaction: t });

    // 2) Datos únicos (también cuentan los usuarios borrados lógicamente)
    const existe = (where) => Usuario.findOne({ where, transaction: t, paranoid: false });
    if (await existe({ email })) throw AppError.conflict('El email ya está registrado', 'EMAILDUPLICADO');
    if (await existe({ tipoDoc: 'CEDULA', cedula: datos.cedula })) throw AppError.conflict('La cédula ya está registrada', 'CEDULADUPLICADA');
    if (await existe({ telefono })) throw AppError.conflict('El teléfono ya está registrado', 'TELEFONODUPLICADO');
    if (placa && await Repartidor.findOne({ where: { placa }, transaction: t, paranoid: false })) {
      throw AppError.conflict('Esta placa ya está registrada por otro repartidor', 'PLACADUPLICADA');
    }

    // 3) Usuario + perfil según el rol
    // La BD genera el USUARIO (clave primaria) a partir del nombre y se registra a sí mismo como creador
    const nuevo = await Usuario.create({
      rol: APIAROL[tipo],
      nombre,
      apellido: datos.apellido.trim(),
      email,
      telefono,
      cedula: datos.cedula,
      passwordHash: claveHash,
      verificado: true,
      emailVerificadoEn: ahora,
      terminosEn: ahora,
      terminosVer: String(terminosVer),
    }, { transaction: t });

    if (tipo === 'vendedor') {
      await VendedorService.crearPerfil(nuevo.id, {
        nombreNegocio: datos.nombreNegocio, descripcion: datos.descripcionNegocio, categoria: datos.categoriaNegocio,
      }, { transaction: t, nombreUsuario: nombre });
    }

    if (tipo === 'repartidor') {
      await RepartidorService.crearPerfil(nuevo.id, datos, { transaction: t });     // la licencia es opcional: se completa luego
    }

    // 4) El código de verificación queda consumido (no sirve para registrar otra cuenta)
    await CodigoService.consumir(verificacion, { transaction: t });
    return nuevo;
  });

  auditar({ usuarioId: usuario.id, accion: 'REGISTRO', entidad: 'USUARIOS', entidadId: usuario.id, detalle: { tipoUsuario: tipo }, req });
  return { usuario: usuarioPublico(usuario), token: TokenService.crear(usuario) };
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
    await usuario.update({
      intentosFallidos: bloquear ? 0 : intentos,
      bloqueadoHasta: bloquear ? new Date(Date.now() + MINUTOSBLOQUEO * 60 * 1000) : null,
    });
    auditar({ usuarioId: usuario.id, accion: 'LOGINFALLIDO', entidad: 'USUARIOS', entidadId: usuario.id, detalle: { intentos, bloqueado: bloquear }, req });
    throw AppError.unauthorized('Credenciales inválidas', 'CREDENCIALESINVALIDAS');
  }

  await usuario.update({ intentosFallidos: 0, bloqueadoHasta: null, ultimaConexion: new Date(), ultimaIp: ipDe(req) });
  auditar({ usuarioId: usuario.id, accion: 'LOGIN', entidad: 'USUARIOS', entidadId: usuario.id, req });
  return { usuario: usuarioPublico(usuario), token: TokenService.crear(usuario) };
}

// ---------------------------------------------------------------------------------------------
// Perfil
// ---------------------------------------------------------------------------------------------
const fotoDe = async (usuario, req) => (await ArchivoService.mapaUrls(req, [usuario.fotoId]))[usuario.fotoId]?.url || null;

async function obtenerPerfil(id, req) {
  const usuario = await Usuario.findByPk(id);
  if (!usuario) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return usuarioPerfil(usuario, await fotoDe(usuario, req));
}

// Recibe la foto en base64, la optimiza (WebP) y guarda su código en USUARIOS.FOTO. Devuelve la URL.
async function subirFoto(id, base64, req) {
  const usuario = await Usuario.findByPk(id);
  if (!usuario) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  const archivo = await ArchivoService.guardarBase64({ base64, categoria: 'PERFIL', propietario: id });
  await withTransaction((t) => usuario.update({ fotoId: archivo.id, actualizadoPor: id }, { transaction: t }), { usuarioId: id });
  auditar({ usuarioId: id, accion: 'FOTOACTUALIZADA', entidad: 'USUARIOS', entidadId: id, req });
  return (await ArchivoService.mapaUrls(req, [archivo.id]))[archivo.id].url;
}

async function actualizarPerfil(id, { nombre, apellido, telefono }, req) {
  const usuario = await Usuario.findByPk(id);
  if (!usuario) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');

  if (telefono && telefono !== usuario.telefono
      && await Usuario.findOne({ where: { telefono }, paranoid: false })) {
    throw AppError.conflict('El teléfono ya está registrado', 'TELEFONODUPLICADO');
  }

  await withTransaction((t) => usuario.update({
    ...(nombre && { nombre: nombre.trim() }),
    ...(apellido && { apellido: apellido.trim() }),
    ...(telefono && { telefono }),
    actualizadoPor: id,
  }, { transaction: t }), { usuarioId: id });

  auditar({ usuarioId: id, accion: 'PERFILACTUALIZADO', entidad: 'USUARIOS', entidadId: id, req });
  return usuarioPerfil(usuario, await fotoDe(usuario, req));
}

async function cambiarClave(id, { passwordActual, passwordNueva }, req) {
  const usuario = await Usuario.findByPk(id);
  if (!usuario) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  if (!(await usuario.verificarClave(passwordActual))) {
    throw AppError.unauthorized('Contraseña actual incorrecta', 'CLAVEACTUALINCORRECTA');
  }
  const claveHash = await hashClave(passwordNueva);
  await withTransaction((t) => usuario.update(
    { passwordHash: claveHash, claveCambiadaEn: new Date(), actualizadoPor: id },
    { transaction: t },
  ), { usuarioId: id });
  auditar({ usuarioId: id, accion: 'CAMBIOCLAVE', entidad: 'USUARIOS', entidadId: id, req });
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
  await withTransaction((t) => usuario.update({
    passwordHash: claveHash, claveCambiadaEn: new Date(), intentosFallidos: 0, bloqueadoHasta: null, actualizadoPor: usuario.id,
  }, { transaction: t }), { usuarioId: usuario.id });

  auditar({ usuarioId: usuario.id, accion: 'RESETCLAVE', entidad: 'USUARIOS', entidadId: usuario.id, req });
}

// ---------------------------------------------------------------------------------------------
// Verificación de email (antes de registrarse)
// ---------------------------------------------------------------------------------------------
async function enviarCodigoEmail({ email: emailEntrada, nombre, fcmToken }, req) {
  const email = normalizarEmail(emailEntrada);

  // No se envían códigos a cuentas que ya existen (evita spam a usuarios registrados)
  if (await Usuario.findOne({ where: { email }, paranoid: false })) {
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
const existeCedula = async (cedula) => (await Usuario.count({ where: { tipoDoc: 'CEDULA', cedula }, paranoid: false })) > 0;
const existeEmail = async (email) => (await Usuario.count({ where: { email: normalizarEmail(email) }, paranoid: false })) > 0;
const existePlaca = async (placa) => (await Repartidor.count({ where: { placa: normalizarPlaca(placa) }, paranoid: false })) > 0;

module.exports = {
  ROLES,
  registrar, login, obtenerPerfil, actualizarPerfil, subirFoto, cambiarClave,
  solicitarCodigoReset, verificarCodigoReset, restablecerClave,
  enviarCodigoEmail, verificarCodigoEmail,
  existeCedula, existeEmail, existePlaca,
};
