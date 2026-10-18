const ConfiguracionService = require('./configuracion.service');
const { distanciaKm } = require('../utils/geo');

// TARIFAS de ValleXpress (TCONFIGURACIONES, las cambia el administrador):
//   envío    = base + porKm × km de ruta (línea recta × factor de ruta), redondeado hacia ARRIBA a 5 centavos
//   comisión = subtotal de productos × porcentaje. Desde 2026-10-18 es 0: ValleXpress cobra una suscripción mensual
//              a vendedores y repartidores (suscripcion.service.js); ya no se puede cambiar desde el panel.
// El repartidor se lleva el 100 % del envío. Precios con IVA incluido: aquí no se suman impuestos.
// Todo se calcula en CENTAVOS (enteros) para no arrastrar errores de punto flotante.
const CLAVES = Object.freeze({
  envioBase: ['ENVIOBASE', 1],
  envioPorKm: ['ENVIOPORKM', 0.3],
  factorRuta: ['ENVIOFACTORRUTA', 1.3],
  comisionPorcentaje: ['COMISIONPORCENTAJE', 10],
});

// Límites razonables para lo que escribe el administrador
const LIMITES = Object.freeze({
  envioBase: [0, 20],
  envioPorKm: [0, 5],
  factorRuta: [1, 3],
});

const numero = (v, porDefecto) => (Number.isFinite(Number(v)) ? Number(v) : porDefecto);

async function tarifas() {
  const salida = {};
  for (const [campo, [clave, porDefecto]] of Object.entries(CLAVES)) {
    salida[campo] = numero(await ConfiguracionService.obtener(clave, porDefecto), porDefecto);
  }
  return salida;
}

const redondearA5 = (centavos) => Math.ceil(Math.round(centavos) / 5) * 5;

// Envío de un punto a otro. Sin coordenadas del local (negocio sin ubicar) se cobra solo la base.
function envioEntre(t, desde, hasta) {
  if (!desde || !hasta) return { distanciaKm: null, centavos: redondearA5(t.envioBase * 100) };
  const km = Number((distanciaKm(desde, hasta) * t.factorRuta).toFixed(2));
  return { distanciaKm: km, centavos: redondearA5((t.envioBase + t.envioPorKm * km) * 100) };
}

const comisionDe = (subtotalCentavos, porcentaje) => Math.round((subtotalCentavos * porcentaje) / 100);

// Cambia las tarifas (solo las que vienen) dentro de la transacción "t"; devuelve lo que cambió
async function fijar(cambios, { transaction } = {}) {
  const actual = await tarifas();
  const hechos = {};
  for (const [campo, valor] of Object.entries(cambios)) {
    if (!CLAVES[campo] || !LIMITES[campo] || valor === undefined || Number(valor) === actual[campo]) continue;   // la comisión ya no se cambia
    await ConfiguracionService.fijar(CLAVES[campo][0], Number(valor), { transaction });
    hechos[campo] = Number(valor);
  }
  return hechos;
}

module.exports = { CLAVES, LIMITES, tarifas, envioEntre, comisionDe, redondearA5, fijar };
