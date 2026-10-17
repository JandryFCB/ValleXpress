const ConfiguracionService = require('./configuracion.service');
const AppError = require('../errors/AppError');
const { distanciaKm } = require('../utils/geo');

// ZONA DE SERVICIO: el círculo donde funciona ValleXpress (TCONFIGURACIONES, la cambia el administrador).
// Por ahora una sola zona (Yantzaza). Radio 0 = sin límite.
const CLAVES = Object.freeze({
  nombre: ['ZONANOMBRE', 'Yantzaza'],
  latitud: ['ZONALATITUD', -3.8277],
  longitud: ['ZONALONGITUD', -78.7593],
  radioKm: ['ZONARADIOKM', 15],
});
const LIMITES = Object.freeze({ latitud: [-90, 90], longitud: [-180, 180], radioKm: [0, 500] });

async function zona() {
  const z = {};
  for (const [campo, [clave, porDefecto]] of Object.entries(CLAVES)) {
    const v = await ConfiguracionService.obtener(clave, porDefecto);
    z[campo] = campo === 'nombre' ? String(v) : Number.isFinite(Number(v)) ? Number(v) : porDefecto;
  }
  return z;
}

async function dentro(punto) {
  const z = await zona();
  if (!z.radioKm) return { dentro: true, zona: z };
  const km = distanciaKm({ lat: z.latitud, lng: z.longitud }, punto);
  return { dentro: km <= z.radioKm, km, zona: z };
}

// Lanza el error para el usuario si el punto queda fuera de la zona
async function exigirDentro(punto, { paraNegocio = false } = {}) {
  const r = await dentro(punto);
  if (r.dentro) return;
  throw AppError.conflict(
    paraNegocio
      ? `Por ahora ValleXpress funciona solo en ${r.zona.nombre} y sus alrededores: tu local debe estar dentro de esa zona`
      : `ValleXpress todavía no llega a esa zona: por ahora funcionamos en ${r.zona.nombre} y sus alrededores. ¡Pronto estaremos allí!`,
    'FUERADEZONA',
    { zona: r.zona.nombre, distanciaKm: Number(r.km.toFixed(1)), radioKm: r.zona.radioKm },
  );
}

async function fijar(cambios, { transaction } = {}) {
  const actual = await zona();
  const hechos = {};
  for (const [campo, valor] of Object.entries(cambios)) {
    if (!CLAVES[campo] || valor === undefined) continue;
    const nuevo = campo === 'nombre' ? String(valor).trim() : Number(valor);
    if (nuevo === actual[campo]) continue;
    await ConfiguracionService.fijar(CLAVES[campo][0], nuevo, { transaction });
    hechos[campo] = nuevo;
  }
  return hechos;
}

module.exports = { CLAVES, LIMITES, zona, dentro, exigirDentro, fijar };
