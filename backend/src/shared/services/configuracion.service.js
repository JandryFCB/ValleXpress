const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');

// Lee TCONFIGURACIONES (clave -> valor JSON, solo la versión vigente) con una caché corta para no consultar
// en cada petición.
const TTLMS = 60 * 1000;
const cache = new Map();

async function obtener(clave, porDefecto = null) {
  const guardado = cache.get(clave);
  if (guardado && guardado.hasta > Date.now()) return guardado.valor;

  const [fila] = await sequelize.query(
    "SELECT valor FROM tconfiguraciones WHERE cconfiguracion = :clave AND fhasta = '2999-12-31 00:00:00-05'",
    { replacements: { clave }, type: QueryTypes.SELECT },
  );
  const valor = fila ? fila.valor : porDefecto;       // pg ya convierte el jsonb a booleano/número/texto
  cache.set(clave, { valor, hasta: Date.now() + TTLMS });
  return valor;
}

const limpiarCache = () => cache.clear();

module.exports = { obtener, limpiarCache };
