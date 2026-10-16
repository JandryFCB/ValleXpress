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

// Cambia el valor vigente (el trigger guarda la versión anterior). Se usa dentro de la transacción de quien
// cambia, para que la auditoría sepa quién fue; la caché se limpia al terminar (ver limpiarCache).
async function fijar(clave, valor, { transaction } = {}) {
  const [, filas] = await sequelize.query(
    "UPDATE tconfiguraciones SET valor = CAST(:valor AS jsonb) WHERE cconfiguracion = :clave AND fhasta = '2999-12-31 00:00:00-05'",
    { replacements: { clave, valor: JSON.stringify(valor) }, transaction },
  );
  if (!filas?.rowCount) throw new Error(`No existe la configuración ${clave}`);
}

module.exports = { obtener, fijar, limpiarCache };
