const crypto = require('crypto');
const { Op } = require('sequelize');
const { sequelize } = require('../../config/database');
const Sesion = require('../../modules/auth/sesion.model');
const Usuario = require('../../modules/auth/usuario.model');
const AppError = require('../errors/AppError');
const { logMensaje } = require('./log.service');

// Sesión persistente (como Uber o Rappi): el login entrega un token de acceso corto (15 min) y un REFRESH TOKEN
// largo. La app guarda el refresh token en almacenamiento cifrado y lo canjea sola cuando el de acceso vence,
// así el usuario no vuelve a escribir su clave mientras use la app.
//
//   * En la BD solo se guarda el HASH (SHA-256) del refresh token: si alguien lee la BD no puede usarlo.
//   * ROTACIÓN: cada canje invalida el token usado y entrega uno nuevo de la misma familia (equipo).
//   * Si llega un token ya usado hace más de GRACIASEG segundos es señal de robo: se revoca toda la familia.
//   * Vence a los DIASVIDA días SIN usar la app: cada rotación renueva el plazo.

const DIASVIDA = Number(process.env.REFRESH_DIAS) || 90;
const GRACIASEG = 10;           // reintento legítimo (la red falló y la app repite): no se trata como robo

const hash = (token) => crypto.createHash('sha256').update(token).digest('hex');
const nuevoToken = () => crypto.randomBytes(48).toString('base64url');
const vence = () => new Date(Date.now() + DIASVIDA * 24 * 60 * 60 * 1000);
const PLATAFORMAS = ['ANDROID', 'IOS', 'WEB'];

const limpiarDispositivo = (d) => ({
  dispositivo: d?.dispositivo ? String(d.dispositivo).slice(0, 100) : null,
  plataforma: PLATAFORMAS.includes(String(d?.plataforma).toUpperCase()) ? String(d.plataforma).toUpperCase() : null,
});

// Abre una sesión nueva (login o registro). Devuelve el refresh token EN CLARO: solo se entrega esta vez.
async function crear(usuarioId, { dispositivo, plataforma, ip, familia } = {}, opciones = {}) {
  const token = nuevoToken();
  await Sesion.create({
    usuarioId,
    familia: familia || crypto.randomUUID(),
    tokenHash: hash(token),
    ip: ip || null,
    expiraEn: vence(),
    ...limpiarDispositivo({ dispositivo, plataforma }),
  }, opciones);
  return token;
}

// Canjea un refresh token por uno nuevo. Devuelve { usuario, refreshToken }; quien llama emite el token de acceso.
async function rotar(refreshToken, ip) {
  if (typeof refreshToken !== 'string' || refreshToken.length < 20) {
    throw AppError.unauthorized('Sesión inválida', 'REFRESHINVALIDO');
  }

  const resultado = await sequelize.transaction(async (t) => {
    const sesion = await Sesion.findOne({ where: { tokenHash: hash(refreshToken) }, transaction: t, lock: t.LOCK.UPDATE });
    if (!sesion) return { error: AppError.unauthorized('Sesión inválida', 'REFRESHINVALIDO') };
    if (sesion.revocadoEn) return { error: AppError.unauthorized('La sesión fue cerrada', 'SESIONCERRADA') };

    if (sesion.usadoEn) {
      // Token ya canjeado. Dentro de la gracia es un reintento; después, alguien lo está reutilizando.
      if (Date.now() - new Date(sesion.usadoEn).getTime() <= GRACIASEG * 1000) {
        return { error: AppError.conflict('La sesión se está renovando, reintenta', 'REFRESHENUSO') };
      }
      await sequelize.query(
        'SELECT REVOCARSESIONES(:usuario, :motivo, CAST(:familia AS uuid))',
        { replacements: { usuario: sesion.usuarioId, motivo: 'REUSO', familia: sesion.familia }, transaction: t },
      );
      return { reuso: sesion };
    }

    if (new Date(sesion.expiraEn) <= new Date()) {
      return { error: AppError.unauthorized('La sesión expiró, inicia sesión de nuevo', 'REFRESHEXPIRADO') };
    }

    const usuario = await Usuario.findByPk(sesion.usuarioId, { transaction: t });
    if (!usuario || !usuario.activo) {
      await sesion.update({ revocadoEn: new Date(), motivoRevocacion: 'DESACTIVADA' }, { transaction: t });
      return { error: AppError.forbidden('Cuenta desactivada', 'CUENTADESACTIVADA') };
    }

    const nuevo = nuevoToken();
    await sesion.update({ usadoEn: new Date() }, { transaction: t });
    await Sesion.create({
      usuarioId: sesion.usuarioId,
      familia: sesion.familia,
      tokenHash: hash(nuevo),
      dispositivo: sesion.dispositivo,
      plataforma: sesion.plataforma,
      ip: ip || sesion.ip,
      expiraEn: vence(),
    }, { transaction: t });
    return { usuario, refreshToken: nuevo };
  });

  if (resultado.reuso) {
    logMensaje({ nivel: 'ADVERTENCIA', modulo: 'SESIONES', accion: 'REFRESHREUTILIZADO', mensaje: 'Se reutilizó un refresh token: se revocó la familia', usuarioId: resultado.reuso.usuarioId, detalle: { familia: resultado.reuso.familia } });
    throw AppError.unauthorized('Por seguridad cerramos la sesión, inicia sesión de nuevo', 'REFRESHREUTILIZADO');
  }
  if (resultado.error) throw resultado.error;
  return { usuario: resultado.usuario, refreshToken: resultado.refreshToken };
}

// Cierra la sesión de este equipo (toda su familia). No exige estar autenticado: el refresh token es la credencial.
async function cerrar(refreshToken) {
  if (typeof refreshToken !== 'string' || !refreshToken) return;
  const sesion = await Sesion.findOne({ where: { tokenHash: hash(refreshToken) } });
  if (!sesion) return;                                                      // cerrar dos veces no es un error
  await sequelize.query(
    'SELECT REVOCARSESIONES(:usuario, :motivo, CAST(:familia AS uuid))',
    { replacements: { usuario: sesion.usuarioId, motivo: 'CIERRE', familia: sesion.familia } },
  );
}

// Cierra todas las sesiones del usuario (cierre en todos los equipos, cambio o restablecimiento de clave)
async function cerrarTodas(usuarioId, motivo = 'CIERRETODAS', opciones = {}) {
  const [filas] = await sequelize.query(
    'SELECT REVOCARSESIONES(:usuario, :motivo) AS n',
    { replacements: { usuario: usuarioId, motivo }, ...opciones },
  );
  return Number(filas?.[0]?.n ?? 0);
}

// Sesiones abiertas del usuario (para mostrar "dispositivos con sesión iniciada")
const listar = (usuarioId) => Sesion.findAll({
  where: { usuarioId, revocadoEn: null, usadoEn: null, expiraEn: { [Op.gt]: new Date() } },
  order: [['creadoEn', 'DESC']],
});

// Dueño de la sesión de un refresh token (o null si no existe)
async function usuarioDe(refreshToken) {
  if (typeof refreshToken !== 'string' || !refreshToken) return null;
  const sesion = await Sesion.findOne({ where: { tokenHash: hash(refreshToken) }, attributes: ['usuarioId'] });
  return sesion?.usuarioId || null;
}

module.exports = { crear, rotar, cerrar, cerrarTodas, listar, usuarioDe, DIASVIDA };
