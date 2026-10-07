const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const { interpretarCategoria } = require('../constants/codigos');

// Lee los catálogos (CODIGO -> DESCRIPCION) con una caché corta y traduce la categoría de la app.
const TABLAS = new Set(['categorias', 'estadopedido', 'estadoproducto', 'estadopago', 'estadoaprobacion', 'metodopago', 'tipovehiculo', 'roles']);
const TTLMS = 5 * 60 * 1000;
const cache = new Map();

async function mapa(tabla) {
  if (!TABLAS.has(tabla)) throw new Error(`Catálogo desconocido: ${tabla}`);
  const guardado = cache.get(tabla);
  if (guardado && guardado.hasta > Date.now()) return guardado.valor;
  const filas = await sequelize.query(
    `SELECT codigo, descripcion FROM ${tabla} WHERE activo AND eliminadoen IS NULL`,   // tabla validada contra la lista blanca
    { type: QueryTypes.SELECT },
  );
  const valor = Object.fromEntries(filas.map((f) => [f.codigo, f.descripcion]));
  cache.set(tabla, { valor, hasta: Date.now() + TTLMS });
  return valor;
}

const capitalizar = (t) => (t ? t.charAt(0).toUpperCase() + t.slice(1).toLowerCase() : t);

// La app maneja la categoría como TEXTO LIBRE ("Comida", "Pizza"); la BD usa el catálogo CATEGORIAS.
// Si el texto coincide con una categoría se guarda su código; si no, se guarda OTROS (099) y el texto original
// queda en DATOSEXTRA ("categoria=Pizza") para devolverlo igual. Cuando la app tenga un selector, esto se simplifica.
function categoriaParaGuardar(texto) {
  const { codigo, conocida } = interpretarCategoria(texto);
  const limpio = String(texto || '').trim();
  return { categoria: codigo, datosExtra: conocida || !limpio ? null : `categoria=${limpio}`.slice(0, 250) };
}

async function categoriaTexto(registro) {
  const extra = registro.datosExtra;
  if (extra && extra.startsWith('categoria=')) return extra.slice('categoria='.length);
  if (!registro.categoria) return null;
  return capitalizar((await mapa('categorias'))[registro.categoria] || null);
}

module.exports = { mapa, categoriaParaGuardar, categoriaTexto };
