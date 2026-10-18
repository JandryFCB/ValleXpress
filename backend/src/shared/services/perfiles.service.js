const ConfiguracionService = require('./configuracion.service');

// Permisos de cada PERFIL (rol que se registra desde la app), guardados en TCONFIGURACIONES:
//   * registroAbierto: si ese perfil puede crear su cuenta desde la app (el administrador siempre puede crearla).
//   * aprobacionAutomatica: si el negocio o el repartidor nace aprobado o espera la revisión del administrador.
//     El cliente no tiene: solo consume, no pasa por revisión.
const PERFILES = Object.freeze({
  cliente: { registro: 'REGISTROCLIENTE' },
  vendedor: { registro: 'REGISTROVENDEDOR', aprobacion: 'APROBACIONAUTOVENDEDOR' },
  repartidor: { registro: 'REGISTROREPARTIDOR', aprobacion: 'APROBACIONAUTOREPARTIDOR' },
});
const ROLESPERFIL = Object.freeze(Object.keys(PERFILES));
const conAprobacion = (rol) => !!PERFILES[rol]?.aprobacion;

// Si falta la configuración: registro abierto, pero aprobación MANUAL (lo seguro es revisar)
const registroAbierto = async (rol) => !!PERFILES[rol] && (await ConfiguracionService.obtener(PERFILES[rol].registro, true)) === true;
const aprobacionAutomatica = async (rol) => conAprobacion(rol) && (await ConfiguracionService.obtener(PERFILES[rol].aprobacion, false)) === true;

async function permisosDe(rol) {
  return {
    rol,
    registroAbierto: await registroAbierto(rol),
    ...(conAprobacion(rol) && { aprobacionAutomatica: await aprobacionAutomatica(rol) }),
  };
}

const permisos = () => Promise.all(ROLESPERFIL.map(permisosDe));

// Guarda los cambios de un perfil dentro de la transacción "t"; devuelve solo lo que cambió de verdad
async function fijar(rol, { registroAbierto: registro, aprobacionAutomatica: aprobacion }, { transaction } = {}) {
  const actual = await permisosDe(rol);
  const cambios = {};
  if (registro !== undefined && registro !== actual.registroAbierto) {
    await ConfiguracionService.fijar(PERFILES[rol].registro, registro, { transaction });
    cambios.registroAbierto = registro;
  }
  if (aprobacion !== undefined && conAprobacion(rol) && aprobacion !== actual.aprobacionAutomatica) {
    await ConfiguracionService.fijar(PERFILES[rol].aprobacion, aprobacion, { transaction });
    cambios.aprobacionAutomatica = aprobacion;
  }
  return cambios;
}

// ---------------------------------------------------------------------------------------------
// Cupo de repartidores: cuántos aprobados (con la cuenta activa) puede haber a la vez. 0 = sin límite.
// ---------------------------------------------------------------------------------------------
const AppError = require('../errors/AppError');

async function cupoRepartidores() {
  const { sequelize } = require('../../config/database');
  const limite = Math.max(0, Number(await ConfiguracionService.obtener('CUPOREPARTIDORES', 0)) || 0);
  const [{ n }] = await sequelize.query(
    `SELECT COUNT(*)::int AS n FROM trepartidores r
       JOIN tusuarios u ON u.cusuario = r.cusuario AND u.fhasta = '2999-12-31 00:00:00-05' AND u.cestatususuario = '001'
      WHERE r.fhasta = '2999-12-31 00:00:00-05' AND r.cestatusaprobacion = '002'`,
    { type: require('sequelize').QueryTypes.SELECT },
  );
  return { limite, ocupados: n, lleno: limite > 0 && n >= limite };
}

// Contacto de soporte: correo (variables del servidor) y WhatsApp (lo pone el administrador)
async function soporte() {
  const correo = require('./correo.service').soporte();
  const whatsapp = String((await ConfiguracionService.obtener('SOPORTEWHATSAPP', '')) || '').trim();
  return { correo: correo || null, whatsapp: whatsapp || null };
}

// Nadie más se registra como repartidor con el cupo lleno: se le dice a quién escribir o que espere
async function exigirCupoRegistro() {
  const cupo = await cupoRepartidores();
  if (!cupo.lleno) return;
  const s = await soporte();
  const contacto = [s.whatsapp && `al WhatsApp ${s.whatsapp}`, s.correo && `a ${s.correo}`].filter(Boolean).join(' o ');
  throw AppError.forbidden(
    `Por ahora no hay cupos para nuevos repartidores.${contacto ? ` Escríbenos ${contacto} para quedar en la lista de espera,` : ''} o vuelve a intentarlo más adelante`,
    'SINCUPOS',
    { soporte: s },
  );
}

module.exports = { ROLESPERFIL, conAprobacion, registroAbierto, aprobacionAutomatica, permisosDe, permisos, fijar, cupoRepartidores, soporte, exigirCupoRegistro };
