const { Op } = require('sequelize');
const CodigoVerificacion = require('../../modules/auth/codigoVerificacion.model');
const { PROPOSITOCODIGO } = require('../constants/codigos');
const { generarCodigo6 } = require('../utils/codes');
const { hashClave, compararClave } = require('../utils/clave');
const AppError = require('../errors/AppError');

// Códigos de 6 dígitos (verificar el correo, recuperar la clave). Viven en TCODIGOSVERIFICACION.

// Crea un código nuevo y devuelve el código EN CLARO (solo para enviarlo por correo/push; en la BD va con hash).
async function generar({ proposito, email, usuarioId = null, ip = null, tokenFcm = null, minutosExpira = 15, esperaSeg = 60 }) {
  const ultimo = await CodigoVerificacion.findOne({
    where: { proposito, email, usadoEn: null },
    order: [['creadoEn', 'DESC']],
  });
  if (ultimo) {
    const transcurrido = (Date.now() - new Date(ultimo.creadoEn).getTime()) / 1000;
    if (transcurrido < esperaSeg) {
      const restante = Math.ceil(esperaSeg - transcurrido);
      throw AppError.tooMany(`Espera ${restante} segundos antes de solicitar un nuevo código`, 'ESPERARCODIGO', { retryAfter: restante });
    }
  }

  // Los códigos anteriores del mismo propósito quedan invalidados
  await CodigoVerificacion.update({ usadoEn: new Date() }, { where: { proposito, email, usadoEn: null } });

  const codigo = generarCodigo6();
  await CodigoVerificacion.create({
    proposito,
    email,
    usuarioId,
    codigoHash: await hashClave(codigo),
    expiraEn: new Date(Date.now() + minutosExpira * 60 * 1000),
    ip,
    tokenFcm,
  });
  return { codigo };
}

// Comprueba el código ingresado. Si es correcto lo marca como verificado y devuelve el registro.
async function verificar({ proposito, email, codigo }) {
  const registro = await CodigoVerificacion.findOne({
    where: { proposito, email, usadoEn: null, verificadoEn: null },
    order: [['creadoEn', 'DESC']],
  });

  if (!registro || new Date(registro.expiraEn) < new Date()) {
    throw AppError.badRequest('Código inválido o expirado', 'CODIGOINVALIDO');
  }
  if (registro.intentos >= registro.maxIntentos) {
    throw AppError.tooMany('Demasiados intentos. Solicita un nuevo código.', 'DEMASIADOSINTENTOS');
  }

  if (!(await compararClave(codigo, registro.codigoHash))) {
    await registro.increment('intentos');
    throw AppError.badRequest('Código incorrecto', 'CODIGOINCORRECTO');
  }

  await registro.update({ verificadoEn: new Date() });
  return registro;
}

const consumir = (registro, opciones = {}) => registro.update({ usadoEn: new Date() }, opciones);

// El registro exige que el correo se haya verificado hace poco y que ese código no se haya usado ya.
async function exigirEmailVerificado(email, { minutos = 60, transaction } = {}) {
  const registro = await CodigoVerificacion.findOne({
    where: {
      proposito: PROPOSITOCODIGO.EMAIL,
      email,
      usadoEn: null,
      verificadoEn: { [Op.gt]: new Date(Date.now() - minutos * 60 * 1000) },
    },
    order: [['verificadoEn', 'DESC']],
    transaction,
  });
  if (!registro) {
    throw AppError.forbidden('Debes verificar tu email antes de registrarte', 'EMAILNOVERIFICADO');
  }
  return registro;
}

module.exports = { generar, verificar, consumir, exigirEmailVerificado };
