const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');

// Lee la tabla CONFIGURACIONES (clave -> valor JSON) con una caché corta para no consultar en cada petición.
const TTLMS = 60 * 1000;
const cache = new Map();

async function obtener(clave, porDefecto = null) {
  const guardado = cache.get(clave);
  if (guardado && guardado.hasta > Date.now()) return guardado.valor;

  const [fila] = await sequelize.query(
    'SELECT valor FROM configuraciones WHERE clave = :clave AND activo AND eliminadoen IS NULL',
    { replacements: { clave }, type: QueryTypes.SELECT },
  );
  const valor = fila ? fila.valor : porDefecto;       // pg ya convierte el jsonb a booleano/número/texto
  cache.set(clave, { valor, hasta: Date.now() + TTLMS });
  return valor;
}

const limpiarCache = () => cache.clear();

// Estado con el que nace un vendedor/repartidor: APROBADO si APROBACIONAUTOMATICA es true (mientras no exista el
// panel de administración), PENDIENTE si es false.
async function aprobacionInicial() {
  const automatica = (await obtener('APROBACIONAUTOMATICA', true)) === true;
  return { aprobacion: automatica ? '002' : '001', aprobadoEn: automatica ? new Date() : null };
}

module.exports = { obtener, limpiarCache, aprobacionInicial };
