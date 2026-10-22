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
const PerfilesService = require('../../shared/services/perfiles.service');
const ArchivoService = require('../../shared/services/archivo.service');
const NegocioService = require('../negocios/negocio.service');
const RepartidorService = require('../repartidores/repartidor.service');
const LegalService = require('../legal/legal.service');
const DocumentosService = require('../repartidores/documentos.service');
const SuscripcionService = require('../suscripciones/suscripcion.service');
const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { logMensaje, auditar } = require('../../shared/services/log.service');
const Correo = require('../../shared/services/correo.service');
const { hashClave, compararClave, HASHRELLENO } = require('../../shared/utils/clave');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');
const { ROLES, APIAROL, ROLESREGISTRABLES, PROPOSITOCODIGO, APROBACION, ESTADOPEDIDO: E } = require('../../shared/constants/codigos');

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

// Perfil completo, con la URL de la foto (o null)
const usuarioPerfil = async (u, req) => ({
  ...usuarioPublico(u),
  fotoPerfil: (await ArchivoService.urlDe(req, u.fotoId))?.url || null,
  createdAt: u.creadoEn,
  ultimaConexion: u.ultimaConexion,
});

// Cuenta bloqueada por intentos fallidos: "retryAfter" (segundos) le permite a la app mostrar la cuenta regresiva
function bloqueoTemporal(hasta) {
  const segundos = Math.max(1, Math.ceil((new Date(hasta) - new Date()) / 1000));
  return AppError.tooMany(
    `Bloqueamos tu cuenta por seguridad tras ${MAXINTENTOSFALLIDOS} intentos fallidos. Intenta en ${Math.ceil(segundos / 60)} min o recupera tu contraseña`,
    'CUENTABLOQUEADA',
    { retryAfter: segundos, bloqueadaHasta: new Date(hasta).toISOString(), soporte: Correo.soporte() },
  );
}

// La cuenta no está activa: bloqueada por el administrador ('003') o dada de baja ('002')
function cuentaInactiva(usuario) {
  const baja = usuario.estatus === '002';
  return AppError.forbidden(
    baja ? 'Tu cuenta está dada de baja. Si quieres volver, escríbenos y la reactivamos' : 'Tu cuenta está bloqueada. Escríbenos para revisar tu caso',
    'CUENTADESACTIVADA',
    { estatus: baja ? 'inactivo' : 'bloqueado', soporte: Correo.soporte() },
  );
}

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
// En desarrollo el código también se imprime en la consola (para probar sin depender del correo).
async function enviarCorreoCodigo(tipo, { email, codigo, nombre }, req) {
  if (process.env.NODE_ENV === 'development') console.log(`[DEV] Código de ${tipo} para ${email}: ${codigo}`);
  try {
    if (tipo === 'reset') await Correo.codigoReset(email, codigo);
    else await Correo.codigoVerificacion(email, codigo, nombre);
    return true;
  } catch (e) {
    logMensaje({ nivel: 'ADVERTENCIA', modulo: 'CORREO', accion: 'ENVIOFALLIDO', mensaje: `No se pudo enviar el correo (${tipo})`, detalle: { error: e.message, tipo }, req });
    return false;
  }
}

// ---------------------------------------------------------------------------------------------
// Registro
// ---------------------------------------------------------------------------------------------
// Crea la persona, la cuenta (el CUSUARIO lo genera la BD a partir del nombre) y el teléfono principal.
// El perfil de negocio (vendedor) o de reparto (repartidor) se completa en sus propios módulos.
// Varios perfiles por persona: la persona es una sola (su cédula y su correo) y tiene a lo sumo una cuenta de cada
// perfil (cliente, vendedor, repartidor). Devuelve la persona si ya existe con ESA cédula y ESE correo y todavía no
// tiene este perfil; null si es nueva. Una cuenta dada de baja o bloqueada también cuenta (no se puede volver a
// registrar el mismo perfil para saltarse una baja).
const NOMBREPERFIL = { cliente: 'cliente', vendedor: 'vendedor', repartidor: 'repartidor', administrador: 'administrador' };
const perfilDuplicado = (tipo) => AppError.conflict(
  `Ya tienes una cuenta de ${NOMBREPERFIL[tipo] || tipo} con esta cédula y este correo. Inicia sesión con ella`, 'PERFILDUPLICADO');

async function personaParaRegistro(tipo, { email, cedula }, t) {
  const porCorreo = await Persona.findOne({ where: { correo: email }, transaction: t });
  const porCedula = await Persona.findOne({ where: { tipoDoc: TIPODOCCEDULA, numeroDoc: cedula }, transaction: t });
  if (!porCorreo && !porCedula) return null;
  if (porCorreo && porCedula && String(porCorreo.id) === String(porCedula.id)) {
    const cuentas = await Usuario.findAll({ where: { personaId: porCorreo.id }, attributes: ['id', 'rol'], transaction: t });
    if (cuentas.some((c) => c.tipoUsuario === tipo)) throw perfilDuplicado(tipo);
    return porCorreo;
  }
  if (porCedula) {
    throw AppError.conflict('Esta cédula ya está registrada con otro correo. Para crear otro perfil usa el mismo correo de tu cuenta', 'CEDULADUPLICADA');
  }
  throw AppError.conflict('Este correo ya está registrado con otra cédula', 'EMAILDUPLICADO');
}

// Crea persona, cuenta, teléfono principal y, según el rol, el negocio o el perfil de reparto, dentro de la
// transacción "t". La usan el registro público (con el correo ya verificado) y el administrador.
// Si el negocio o el repartidor nacen aprobados lo decide el permiso de su perfil, salvo que se indique "aprobado".
async function crearCuenta(tipo, datos, t, { correoVerificadoEn = new Date(), aprobado } = {}) {
  const email = normalizarEmail(datos.email);
  const telefono = normalizarTelefono(datos.telefono);
  const ahora = new Date();

  // Una persona (cédula + correo) puede tener una cuenta por perfil: si ya existe se le agrega este perfil
  const existente = await personaParaRegistro(tipo, { email, cedula: datos.cedula }, t);
  const telefonoUsado = await Telefono.findOne({ where: { numero: telefono }, transaction: t });
  if (telefonoUsado && String(telefonoUsado.personaId) !== String(existente?.id)) throw AppError.conflict('El teléfono ya está registrado', 'TELEFONODUPLICADO');

  // Persona -> cuenta -> teléfono (la BD asigna CPERSONA desde el 2 y genera el CUSUARIO)
  const persona = existente || await Persona.create({
    tipoDoc: TIPODOCCEDULA,
    numeroDoc: datos.cedula,
    nombres: datos.nombre.trim(),
    apellidos: datos.apellido.trim(),
    correo: email,
    correoVerificadoEn,
  }, { transaction: t });

  const nueva = await UsuarioCuenta.create({
    personaId: persona.id,
    rol: APIAROL[tipo],
    claveHash: await hashClave(datos.password),
    terminosEn: ahora,
    terminosVer: LegalService.versionDe(`terminos-${tipo}`),
  }, { transaction: t });

  if (!telefonoUsado) await Telefono.create({ personaId: persona.id, numero: telefono, principal: !existente }, { transaction: t });

  // El vendedor nace con su negocio (nombre y categoría; el resto lo completa en "Mi negocio")
  if (tipo === 'vendedor' && datos.nombreNegocio?.trim()) {
    await NegocioService.crearParaUsuario(nueva.id, { nombre: datos.nombreNegocio, categoria: datos.categoriaNegocio, aprobado }, { transaction: t });
  }
  // El repartidor nace con su perfil de reparto (vehículo y placa; la placa se valida según el vehículo)
  if (tipo === 'repartidor' && datos.vehiculo) {
    await RepartidorService.crearPerfil(nueva.id, { vehiculo: datos.vehiculo, placa: datos.placa, color: datos.color, aprobado }, { transaction: t });
  }
  return nueva;
}

// El administrador puede cerrar el registro de un perfil (Perfiles y permisos): la app ya no lo ofrece y el
// servidor lo rechaza. Las cuentas que crea el administrador no pasan por aquí.
const PLURAL = { cliente: 'clientes', vendedor: 'negocios', repartidor: 'repartidores' };
async function exigirRegistroAbierto(tipo) {
  if (!(await PerfilesService.registroAbierto(tipo))) {
    throw AppError.forbidden(`Por ahora no estamos recibiendo nuevos ${PLURAL[tipo]}. Vuelve a intentarlo más adelante`, 'REGISTROCERRADO');
  }
}

// Qué perfiles puede elegir la pantalla de registro (y si el de repartidor ya no tiene cupos, con a quién escribir)
const perfilesRegistro = async () => Object.fromEntries((await PerfilesService.permisos()).map((p) => [p.rol, p.registroAbierto]));
const cuposRegistro = async () => ({ repartidor: (await PerfilesService.cupoRepartidores()).lleno, soporte: await PerfilesService.soporte() });

async function registrar(datos, req) {
  const tipo = datos.tipoUsuario || 'cliente';
  if (!ROLESREGISTRABLES.includes(tipo)) throw AppError.badRequest('Tipo de usuario inválido', 'TIPOUSUARIOINVALIDO');
  await exigirRegistroAbierto(tipo);
  if (tipo === 'repartidor') await PerfilesService.exigirCupoRegistro();
  const email = normalizarEmail(datos.email);

  const cuenta = await withTransaction(async (t) => {
    // El email debe haberse verificado (la app ya lo exige; también el servidor)
    const verificacion = await CodigoService.exigirEmailVerificado(email, { transaction: t });
    const nueva = await crearCuenta(tipo, datos, t, { correoVerificadoEn: verificacion.verificadoEn || new Date() });
    // Prueba de que aceptó los términos de su perfil y la política de privacidad vigentes
    await LegalService.aceptarAlRegistrarse(nueva.id, tipo, req, { transaction: t });
    // El código de verificación queda consumido (no sirve para registrar otra cuenta)
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
// "email" puede traer el correo o el usuario (jcayapa): si lleva @ es un correo.
// Una persona puede tener varias cuentas con el mismo correo (una por perfil): se entra a la que tenga esa clave; si
// varias la comparten, la app pregunta con cuál ("ELEGIRCUENTA") y repite el login con "tipoUsuario".
async function login({ email: identificador, password, tipoUsuario }, req) {
  const id = normalizarEmail(identificador);
  let candidatos = id.includes('@') ? await Usuario.findAll({ where: { email: id }, order: [['rol', 'ASC']] }) : [await Usuario.findOne({ where: { id } })].filter(Boolean);
  if (tipoUsuario) candidatos = candidatos.filter((c) => c.tipoUsuario === tipoUsuario);

  if (!candidatos.length) {
    await compararClave(password, HASHRELLENO);     // mismo tiempo de respuesta exista o no la cuenta
    throw AppError.unauthorized('Credenciales inválidas', 'CREDENCIALESINVALIDAS');
  }

  let usuario = candidatos[0];
  if (candidatos.length > 1) {
    // Varias cuentas: cuentan las que pueden entrar ahora (activas y sin bloqueo temporal)
    const ahora = new Date();
    const habilitadas = candidatos.filter((c) => c.activo && !(c.bloqueadoHasta && new Date(c.bloqueadoHasta) > ahora));
    const coinciden = [];
    for (const c of habilitadas) if (await c.verificarClave(password)) coinciden.push(c);
    if (coinciden.length > 1) {
      throw AppError.conflict('Tienes varias cuentas con este correo: elige con cuál quieres entrar', 'ELEGIRCUENTA', {
        cuentas: coinciden.map((c) => ({ usuario: c.id, tipoUsuario: c.tipoUsuario })),
      });
    }
    if (coinciden.length === 1) return entrar(coinciden[0], req);
    // Ninguna coincide: si todas están inactivas o bloqueadas se dice eso. Si no, el intento fallido cuenta SOLO en
    // la cuenta a la que intentaba entrar: la que eligió o, si entró con el correo, la que usó por última vez.
    if (!habilitadas.length) {
      if (!usuario.activo) throw cuentaInactiva(usuario);
      throw bloqueoTemporal(usuario.bloqueadoHasta);
    }
    const ultima = [...habilitadas].sort((a, b) => new Date(b.ultimaConexion || 0) - new Date(a.ultimaConexion || 0))[0];
    return registrarFallo(ultima, req, { lanzar: true });
  }

  // Cuenta bloqueada o dada de baja por el administrador: se dice claramente y a quién escribir
  if (!usuario.activo) throw cuentaInactiva(usuario);

  if (usuario.bloqueadoHasta && new Date(usuario.bloqueadoHasta) > new Date()) throw bloqueoTemporal(usuario.bloqueadoHasta);

  if (!(await usuario.verificarClave(password))) return registrarFallo(usuario, req, { lanzar: true });
  return entrar(usuario, req);
}

// Clave incorrecta: suma el intento y, al llegar al máximo, bloquea la cuenta unos minutos
async function registrarFallo(usuario, req, { lanzar = true } = {}) {
  const intentos = usuario.intentosFallidos + 1;
  const bloquear = intentos >= MAXINTENTOSFALLIDOS;
  const hasta = new Date(Date.now() + MINUTOSBLOQUEO * 60 * 1000);
  await UsuarioAcceso.update({ intentos: bloquear ? 0 : intentos, bloqueadoHasta: bloquear ? hasta : null }, { where: { id: usuario.id } });
  auditar({ usuarioId: usuario.id, accion: 'LOGINFALLIDO', entidad: 'USUARIOS', entidadId: usuario.id, detalle: { intentos, bloqueado: bloquear }, req });
  if (!lanzar) return;
  if (bloquear) {
    Correo.bloqueoTemporal({ para: usuario.email, nombre: usuario.nombre, minutos: MINUTOSBLOQUEO });
    throw bloqueoTemporal(hasta);
  }
  // Avisa antes de bloquear: en los dos últimos intentos dice cuántos le quedan
  const restantes = MAXINTENTOSFALLIDOS - intentos;
  if (restantes > 2) throw AppError.unauthorized('Credenciales inválidas', 'CREDENCIALESINVALIDAS');
  throw AppError.unauthorized(
    `Contraseña incorrecta. Te ${restantes === 1 ? 'queda 1 intento' : `quedan ${restantes} intentos`} antes de que bloqueemos tu cuenta ${MINUTOSBLOQUEO} minutos`,
    'CREDENCIALESINVALIDAS',
    { intentosRestantes: restantes },
  );
}

async function entrar(usuario, req) {
  await UsuarioAcceso.update({ intentos: 0, bloqueadoHasta: null, ultimaConexion: new Date(), ultimaIp: ipDe(req) }, { where: { id: usuario.id } });
  auditar({ usuarioId: usuario.id, accion: 'LOGIN', entidad: 'USUARIOS', entidadId: usuario.id, req });
  return { usuario: usuarioPublico(usuario), ...(await abrirSesion(usuario, req)) };
}

// Las cuentas de la persona (una por perfil), para cambiar de cuenta sin salir de la app. La actual va marcada.
// estado: activo | temporal (bloqueada unos minutos por contraseñas incorrectas, con "hasta") | bloqueado (por el
// administrador) | inactivo (dada de baja). Así la app explica qué pasa en vez de pedir una contraseña que no sirve.
async function misCuentas(usuarioId) {
  const yo = await cargarUsuario(usuarioId);
  const cuentas = await Usuario.findAll({ where: { personaId: yo.personaId }, attributes: ['id', 'rol', 'estatus', 'activo', 'bloqueadoHasta'], order: [['rol', 'ASC']] });
  const ahora = new Date();
  return cuentas.map((c) => {
    const temporal = c.activo && c.bloqueadoHasta && new Date(c.bloqueadoHasta) > ahora;
    const estado = !c.activo ? (c.estatus === '002' ? 'inactivo' : 'bloqueado') : temporal ? 'temporal' : 'activo';
    return { usuario: c.id, tipoUsuario: c.tipoUsuario, actual: c.id === usuarioId, estado, ...(temporal && { hasta: c.bloqueadoHasta }) };
  });
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

// El repartidor con una entrega en curso (aceptada o recogida) no puede cerrar sesión: el cliente y el negocio lo
// están esperando y su ubicación se dejaría de ver. Al cerrar sesión deja de estar "En línea".
async function exigirSinEntregaEnCurso(usuarioId) {
  if (!usuarioId) return;
  const [f] = await consulta(
    `SELECT cpedido FROM tpedidos WHERE fhasta = '2999-12-31 00:00:00-05' AND cusuario_repartidor = :u AND cestatuspedido IN (:estados) LIMIT 1`,
    { u: usuarioId, estados: [E.ENCAMINO, E.RECOGIDO] },
  );
  if (f) {
    throw AppError.conflict(`Tienes la entrega del pedido #${f.cpedido} en curso. Termínala antes de cerrar sesión`, 'ENTREGAENCURSO', { pedidoId: Number(f.cpedido) });
  }
}
const desconectarRepartidor = (usuarioId) => sequelize.query(
  'UPDATE trepartidoresestado SET estadisponible = FALSE, fultimocambio = now() WHERE cusuario = :u AND estadisponible',
  { replacements: { u: usuarioId } },
).catch(() => {});

// Cierra la sesión de este equipo
async function cerrarSesion({ refreshToken }, req) {
  const usuarioId = await SesionService.usuarioDe(refreshToken);
  await exigirSinEntregaEnCurso(usuarioId);
  await SesionService.cerrar(refreshToken);
  if (usuarioId) await desconectarRepartidor(usuarioId);
  auditar({ usuarioId, accion: 'LOGOUT', entidad: 'USUARIOS', req });
}

// Cierra la sesión en todos los equipos del usuario
async function cerrarTodasLasSesiones(usuarioId, req) {
  await exigirSinEntregaEnCurso(usuarioId);
  const cerradas = await SesionService.cerrarTodas(usuarioId, 'CIERRETODAS');
  await desconectarRepartidor(usuarioId);
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

async function obtenerPerfil(id, req) {
  return usuarioPerfil(await cargarUsuario(id), req);
}

// La foto llega en base64, se optimiza (WebP, sin datos GPS) y queda en TPERSONAS con historial. Devuelve su URL.
// "actor" es quien hace el cambio (el propio usuario o el administrador)
async function subirFoto(id, base64, req, { actor = id } = {}) {
  const usuario = await cargarUsuario(id);
  const archivo = await withTransaction(async (t) => {
    const a = await ArchivoService.guardarBase64({ base64, categoria: 'PERFIL', propietario: id }, { transaction: t });
    await Persona.update({ fotoId: a.id }, { where: { id: usuario.personaId }, transaction: t });
    return a;
  }, { usuarioId: actor });
  auditar({ usuarioId: actor, accion: 'FOTOACTUALIZADA', entidad: 'USUARIOS', entidadId: id, req });
  return (await ArchivoService.urlDe(req, archivo.id))?.url || null;
}

// Quita la foto de perfil: vuelven las iniciales. Es un dato personal, así que se borra también del historial y
// del disco (si ninguna otra persona la usa). Vale para todas las cuentas de la persona.
async function eliminarFoto(id, req) {
  const usuario = await cargarUsuario(id);
  const [persona] = await consulta(`SELECT carchivo_foto AS foto FROM tpersonas WHERE cpersona = :p AND fhasta = '2999-12-31 00:00:00-05'`, { p: usuario.personaId });
  if (!persona?.foto) return { eliminada: false };
  await withTransaction(async (t) => {
    await sequelize.query("SELECT set_config('vallexpress.borrado', 'si', true)", { transaction: t });
    await sequelize.query('UPDATE tpersonas SET carchivo_foto = NULL WHERE cpersona = :p', { replacements: { p: usuario.personaId }, transaction: t });
    await sequelize.query("SELECT set_config('vallexpress.borrado', '', true)", { transaction: t });
  }, { usuarioId: id });
  const [enUso] = await consulta('SELECT 1 FROM tpersonas WHERE carchivo_foto = :f LIMIT 1', { f: persona.foto });
  if (!enUso) await borrarArchivos([Number(persona.foto)]);
  auditar({ usuarioId: id, accion: 'FOTOELIMINADA', entidad: 'USUARIOS', entidadId: id, req });
  return { eliminada: true };
}

// Borra archivos (fila y las 3 versiones del disco). Fuera de transacciones: si el disco falla, no se revierte nada.
async function borrarArchivos(ids) {
  if (!ids.length) return;
  const archivos = await consulta('SELECT carchivo, ruta, rutamediana, rutaminiatura FROM tarchivos WHERE carchivo IN (:ids)', { ids });
  for (const a of archivos) {
    await Promise.all([a.ruta, a.rutamediana, a.rutaminiatura].filter(Boolean).map((r) => fs.rm(path.join(RAIZUPLOADS, String(r).replace(/^uploads\//, '')), { force: true }).catch(() => {})));
  }
  await sequelize.query('DELETE FROM tarchivos WHERE carchivo IN (:ids)', { replacements: { ids } });
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
  return usuarioPerfil(await cargarUsuario(id), req);
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
// Eliminar la cuenta (derecho de eliminación de la LOPDP; Google Play lo exige dentro de la app)
// ---------------------------------------------------------------------------------------------
// Con la contraseña. No se puede con un pedido en curso (como cliente, negocio o repartidor) ni, si es un negocio,
// con comisiones por pagar. Da de baja la cuenta, cierra todas sus sesiones, suspende su negocio y borra sus datos
// personales también del historial (ELIMINARDATOSPERSONALES). Los pedidos se conservan sin datos de contacto.
const ENCURSO = [E.PENDIENTE, E.CONFIRMADO, E.PREPARANDO, E.LISTO, E.ENCAMINO, E.RECOGIDO];
const RAIZUPLOADS = process.env.UPLOADS_DIR || path.join(__dirname, '../../../uploads');
const consulta = (sql, replacements, opciones = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT, ...opciones });

async function eliminarCuenta(id, { password }, req) {
  const usuario = await cargarUsuario(id);
  if (usuario.tipoUsuario === 'administrador') throw AppError.forbidden('La cuenta del administrador no se puede eliminar desde la app', 'ADMINNOELIMINABLE');
  if (!(await usuario.verificarClave(password))) throw AppError.unauthorized('Contraseña incorrecta', 'CLAVEACTUALINCORRECTA');

  const negocios = (await consulta("SELECT cnegocio AS id FROM tnegocios WHERE cusuario = :u AND fhasta = '2999-12-31 00:00:00-05'", { u: id })).map((n) => Number(n.id));
  const [enCurso] = await consulta(
    `SELECT COUNT(*) AS total FROM tpedidos
      WHERE fhasta = '2999-12-31 00:00:00-05' AND cestatuspedido IN (:estados)
        AND (cusuario = :u OR cusuario_repartidor = :u ${negocios.length ? 'OR cnegocio IN (:negocios)' : ''})`,
    { u: id, estados: ENCURSO, ...(negocios.length && { negocios }) },
  );
  if (Number(enCurso.total) > 0) throw AppError.conflict('Tienes un pedido en curso. Espera a que termine para eliminar tu cuenta', 'PEDIDOENCURSO');

  // Vendedor o repartidor con meses de suscripción vencidos: primero se pone al día
  if (['vendedor', 'repartidor'].includes(usuario.tipoUsuario)) {
    const cuenta = await SuscripcionService.estado(id);
    const debe = cuenta.meses.filter((m) => m.estado === 'vencido').reduce((t, m) => t + m.monto, 0);
    if (debe > 0) throw AppError.conflict(`Tienes $${debe.toFixed(2)} de tu suscripción por pagar. Págala en "Mi suscripción" antes de eliminar tu cuenta`, 'SUSCRIPCIONPENDIENTE');
  }

  if (['vendedor', 'repartidor'].includes(usuario.tipoUsuario)) await SuscripcionService.registrarBeneficios({ usuarios: [id] });
  const fotos = await withTransaction(async (t) => {
    await UsuarioCuenta.update({ estatus: '002', claveHash: await hashClave(crypto.randomBytes(24).toString('hex')) }, { where: { id }, transaction: t });
    if (negocios.length) {
      await sequelize.query(
        `UPDATE tnegocios SET cestatusaprobacion = :suspendido, motivoaprobacion = 'El dueño eliminó su cuenta'
          WHERE cusuario = :u AND fhasta = '2999-12-31 00:00:00-05'`,
        { replacements: { u: id, suspendido: APROBACION.SUSPENDIDO }, transaction: t },
      );
      // Sus cuentas bancarias (titular, cédula) son datos personales
      await sequelize.query('DELETE FROM tnegociocuentas WHERE cnegocio IN (:negocios)', { replacements: { negocios }, transaction: t });
    }
    await sequelize.query('DELETE FROM tcodigosverificacion WHERE correo = :correo', { replacements: { correo: usuario.email }, transaction: t });
    await SesionService.cerrarTodas(id, 'DESACTIVADA', { transaction: t });
    const documentos = await DocumentosService.quitarTodos(id, { transaction: t });
    const filas = await consulta('SELECT eliminardatospersonales AS id FROM ELIMINARDATOSPERSONALES(:p, :u)', { p: usuario.personaId, u: id }, { transaction: t });
    return [...new Set([...filas.map((f) => Number(f.id)), ...documentos])];
  }, { usuarioId: id });

  // Las fotos de perfil y de los documentos se borran del disco (fuera de la transacción: si falla no se revierte la baja)
  await borrarArchivos(fotos);

  auditar({ usuarioId: id, accion: 'CUENTAELIMINADA', entidad: 'USUARIOS', entidadId: id, detalle: { tipoUsuario: usuario.tipoUsuario, negocios }, req });
  return { eliminada: true };
}

// ---------------------------------------------------------------------------------------------
// Recuperar contraseña: 1) pedir código  2) verificarlo  3) fijar la clave nueva
// ---------------------------------------------------------------------------------------------
const MENSAJERESET = 'Si el correo existe, te enviamos un código de verificación.';

// Recuperar la contraseña es POR CUENTA (usuario + rol): con el mismo correo la persona puede tener cuenta de cliente,
// de negocio y de repartidor, y solo cambia la que elige. Las cuentas de ADMINISTRADOR no se recuperan por correo
// (quien entrara al correo tomaría el panel): las cambia otro administrador o él mismo desde Configuración.
const recuperables = (cuentas) => cuentas.filter((c) => c.tipoUsuario !== 'administrador' && !String(c.email || '').endsWith('@vallexpress.invalid'));
const NOMBREROL = { cliente: 'cliente', vendedor: 'negocio', repartidor: 'repartidor', administrador: 'administrador' };

async function solicitarCodigoReset(emailEntrada, req) {
  const email = normalizarEmail(emailEntrada);
  const cuentas = await Usuario.findAll({ where: { email } });
  const validas = recuperables(cuentas);

  // Se genera igual exista o no la cuenta (así la respuesta no revela si el correo está registrado)
  const { codigo } = await CodigoService.generar({
    proposito: PROPOSITOCODIGO.RESETCLAVE, email, usuarioId: validas[0]?.id ?? null, ip: ipDe(req), minutosExpira: 10,
  });

  // El correo solo se envía a cuentas reales y sin esperar la respuesta del proveedor
  // (esperarla haría la petición más lenta cuando el correo existe, y delataría la cuenta).
  if (validas.length) enviarCorreoCodigo('reset', { email, codigo }, req);
  else if (cuentas.length) {
    // Solo tiene cuenta de administrador: se le explica por correo (la respuesta sigue siendo la misma)
    Correo.avisoCuenta({
      para: email, nombre: cuentas[0].nombre, asunto: 'Recuperar la contraseña de ValleXpress', titulo: 'Tu cuenta es de administrador',
      parrafos: ['Las cuentas de administrador no se recuperan con un código por correo, para proteger el panel.',
        'Pídele a otro administrador que te ponga una contraseña nueva desde Usuarios, o cámbiala desde Configuración si aún tienes la sesión abierta.'],
    });
  }
  return { message: MENSAJERESET };
}

// Con el código correcto: si tiene una sola cuenta recuperable entrega su resetToken; si tiene varias, la lista para
// que elija cuál (cada una con su propio resetToken).
async function verificarCodigoReset({ email: emailEntrada, code }) {
  const email = normalizarEmail(emailEntrada);
  const registro = await CodigoService.verificar({ proposito: PROPOSITOCODIGO.RESETCLAVE, email, codigo: code });
  const validas = recuperables(await Usuario.findAll({ where: { email }, order: [['rol', 'ASC']] }));
  if (!validas.length) throw AppError.badRequest('Código inválido o expirado', 'CODIGOINVALIDO');

  await CodigoService.consumir(registro);
  const ahora = new Date();
  const cuentas = validas.map((c) => ({
    usuario: c.id, tipoUsuario: c.tipoUsuario, resetToken: TokenService.crearReset(c),
    estado: !c.activo ? (c.estatus === '002' ? 'inactivo' : 'bloqueado') : c.bloqueadoHasta && new Date(c.bloqueadoHasta) > ahora ? 'temporal' : 'activo',
  }));
  return cuentas.length === 1 ? { resetToken: cuentas[0].resetToken, usuario: cuentas[0].usuario, tipoUsuario: cuentas[0].tipoUsuario } : { cuentas };
}

// Fija la contraseña nueva SOLO de esa cuenta: la desbloquea si estaba bloqueada por intentos (no si la bloqueó el
// administrador), cierra sus sesiones y le avisa por correo qué usuario cambió.
async function restablecerClave({ resetToken, newPassword }, req) {
  const payload = TokenService.verificarReset(resetToken);
  const usuario = await Usuario.findOne({ where: { id: payload.userId, email: payload.email } });
  if (!usuario || usuario.tipoUsuario === 'administrador') throw AppError.unauthorized('Token inválido', 'TOKENRESETINVALIDO');

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
  Correo.avisoCuenta({
    para: usuario.email, nombre: usuario.nombre, asunto: 'Cambiaste tu contraseña de ValleXpress', titulo: 'Tu contraseña se actualizó',
    parrafos: [`Se actualizó la contraseña de tu usuario <strong>${usuario.id}</strong> (cuenta de ${NOMBREROL[usuario.tipoUsuario] || usuario.tipoUsuario}).`,
      ...(usuario.activo ? [] : ['Esta cuenta sigue bloqueada por el equipo de ValleXpress: escríbenos para revisar tu caso.']),
      'Tus otras cuentas con este correo no cambiaron.'],
    avisoFinal: 'Si no fuiste tú, escríbenos de inmediato.',
  });
  return { usuario: usuario.id, tipoUsuario: usuario.tipoUsuario, bloqueada: !usuario.activo };
}

// ---------------------------------------------------------------------------------------------
// Verificación de email (antes de registrarse)
// ---------------------------------------------------------------------------------------------
async function enviarCodigoEmail({ email: emailEntrada, nombre, fcmToken, tipoUsuario }, req) {
  const email = normalizarEmail(emailEntrada);

  // A un correo ya registrado solo se le envía código si está creando OTRO perfil (repartidor teniendo cuenta de
  // cliente, por ejemplo). Sin perfil (versiones viejas de la app) o con el perfil que ya tiene, se rechaza.
  const persona = await Persona.findOne({ where: { correo: email } });
  if (persona) {
    if (!tipoUsuario) throw AppError.conflict('El email ya está registrado', 'EMAILDUPLICADO');
    if (await tienePerfil(persona.id, tipoUsuario)) throw perfilDuplicado(tipoUsuario);
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
// Con "tipo" (el perfil que está creando) solo se considera ocupado si esa persona ya tiene ese perfil; si existe
// con otro perfil, "otroPerfil" avisa que puede agregarlo con la misma cédula y el mismo correo.
const tienePerfil = async (personaId, tipo) => (await Usuario.findAll({ where: { personaId }, attributes: ['id', 'rol'] })).some((c) => c.tipoUsuario === tipo);
async function consultarUnico(where, tipo) {
  const persona = await Persona.findOne({ where, attributes: ['id'] });
  if (!persona) return { exists: false, otroPerfil: false };
  if (!tipo) return { exists: true, otroPerfil: false };
  const mismo = await tienePerfil(persona.id, tipo);
  return { exists: mismo, otroPerfil: !mismo };
}
const existeCedula = (cedula, tipo) => consultarUnico({ tipoDoc: TIPODOCCEDULA, numeroDoc: cedula }, tipo);
// Con la cédula que ya escribió: si el correo es de una persona con otra cédula, "otraCedula" (no podrá registrarse)
async function existeEmail(email, tipo, cedula) {
  const r = await consultarUnico({ correo: normalizarEmail(email) }, tipo);
  if (!cedula || (!r.exists && !r.otroPerfil)) return { ...r, otraCedula: false };
  const persona = await Persona.findOne({ where: { correo: normalizarEmail(email) }, attributes: ['tipoDoc', 'numeroDoc'] });
  const otraCedula = !!persona && !(persona.tipoDoc === TIPODOCCEDULA && persona.numeroDoc === cedula);
  return otraCedula ? { exists: true, otroPerfil: false, otraCedula } : { ...r, otraCedula };
}

module.exports = {
  ROLES,
  registrar, perfilesRegistro, cuposRegistro, crearCuenta, usuarioPerfil, login, misCuentas, refrescar, cerrarSesion, cerrarTodasLasSesiones,
  obtenerPerfil, actualizarPerfil, subirFoto, eliminarFoto, cambiarClave, eliminarCuenta,
  solicitarCodigoReset, verificarCodigoReset, restablecerClave,
  enviarCodigoEmail, verificarCodigoEmail,
  existeCedula, existeEmail,
};
