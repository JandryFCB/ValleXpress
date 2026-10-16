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

module.exports = { ROLESPERFIL, conAprobacion, registroAbierto, aprobacionAutomatica, permisosDe, permisos, fijar };
