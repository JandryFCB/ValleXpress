const crypto = require('crypto');
const { sequelize } = require('../../config/database');

// Escribe en LOGERRORES, LOGMENSAJES y AUDITORIA. REGLAS:
//   * Un log NUNCA debe romper la petición: todas las funciones capturan sus propios errores.
//   * Nunca se guardan contraseñas, tokens ni códigos: limpiar() los oculta antes de insertar.
// (Los nombres de tablas y columnas se escriben sin comillas: PostgreSQL los toma en minúsculas.)

const SENSIBLE = /pass|clave|token|secret|authorization|cookie|codigo|code|tarjeta|card|cvv|hash/i;
const MAXTEXTO = 500;
const MAXPROFUNDIDAD = 4;

function limpiar(valor, profundidad = 0) {
  if (valor == null) return valor;
  if (typeof valor === 'string') return valor.length > MAXTEXTO ? `${valor.slice(0, MAXTEXTO)}…` : valor;
  if (typeof valor !== 'object') return valor;
  if (profundidad >= MAXPROFUNDIDAD) return '[PROFUNDO]';
  if (Array.isArray(valor)) return valor.slice(0, 20).map((v) => limpiar(v, profundidad + 1));
  const salida = {};
  for (const [k, v] of Object.entries(valor)) {
    salida[k] = SENSIBLE.test(k) ? '[OCULTO]' : limpiar(v, profundidad + 1);
  }
  return salida;
}

const aJson = (v) => (v == null ? null : JSON.stringify(limpiar(v)));
const ipDe = (req) => (req && req.ip ? String(req.ip).replace(/^::ffff:/, '') : null);
const entorno = () => process.env.NODE_ENV || 'development';

async function insertar(sql, replacements) {
  try {
    await sequelize.query(sql, { replacements });
  } catch (e) {
    console.error('⚠️  No se pudo escribir el log:', e.message);
  }
}

// Error técnico -> LOGERRORES
function logError(err, req, extra = {}) {
  // Ruta completa sin query string (la query puede traer datos sensibles). En el manejador global
  // req.baseUrl/req.path ya están reiniciados, por eso se usa originalUrl.
  const ruta = req?.originalUrl ? String(req.originalUrl).split('?')[0] : null;
  const modulo = extra.modulo || (ruta && ruta.replace(/^\/api\//, '').split('/')[0].toUpperCase()) || 'API';
  const codigo = err.code && typeof err.code === 'string' ? err.code.slice(0, 50) : null;
  const huella = crypto.createHash('sha256').update(`${modulo}|${codigo}|${err.message}`).digest('hex');
  return insertar(
    `INSERT INTO logerrores
       (nivel, modulo, origen, codigo, mensaje, stack, huella, metodo, ruta, estadohttp,
        parametros, cuerpo, usuario, pedido, solicitudid, ip, useragent, entorno)
     VALUES (:nivel, :modulo, 'BACKEND', :codigo, :mensaje, :stack, :huella, :metodo, :ruta, :estado,
        CAST(:parametros AS jsonb), CAST(:cuerpo AS jsonb), :usuarioId, :pedidoId, :solicitudId, :ip, :userAgent, :entorno)`,
    {
      nivel: extra.critico ? 'CRITICO' : 'ERROR',
      modulo,
      codigo,
      mensaje: String(err.message || 'Error sin mensaje').slice(0, 2000),
      stack: err.stack ? String(err.stack).slice(0, 8000) : null,
      huella,
      metodo: req?.method || null,
      ruta: ruta ? ruta.slice(0, 500) : null,
      estado: extra.estado || err.status || null,
      parametros: aJson({ query: req?.query, params: req?.params }),
      cuerpo: aJson(req?.body),
      usuarioId: req?.usuario?.id || null,
      pedidoId: extra.pedidoId || null,
      solicitudId: req?.solicitudId || null,
      ip: ipDe(req),
      userAgent: req?.headers?.['user-agent'] ? String(req.headers['user-agent']).slice(0, 300) : null,
      entorno: entorno(),
    },
  );
}

// Evento del sistema -> LOGMENSAJES  (nivel: DEBUG | INFO | ADVERTENCIA)
function logMensaje({ nivel = 'INFO', modulo, accion = null, mensaje, detalle = null, req = null, usuarioId = null, pedidoId = null }) {
  return insertar(
    `INSERT INTO logmensajes
       (nivel, modulo, accion, mensaje, detalle, usuario, pedido, solicitudid, ip, entorno)
     VALUES (:nivel, :modulo, :accion, :mensaje, CAST(:detalle AS jsonb), :usuarioId, :pedidoId, :solicitudId, :ip, :entorno)`,
    {
      nivel, modulo, accion, mensaje: String(mensaje).slice(0, 2000),
      detalle: aJson(detalle) || '{}',
      usuarioId: usuarioId || req?.usuario?.id || null,
      pedidoId,
      solicitudId: req?.solicitudId || null,
      ip: ipDe(req),
      entorno: entorno(),
    },
  );
}

// Acción de un usuario -> AUDITORIA  (LOGIN, LOGINFALLIDO, REGISTRO, CAMBIOCLAVE...)
function auditar({ usuarioId = null, accion, entidad = null, entidadId = null, detalle = null, req = null }) {
  return insertar(
    `INSERT INTO auditoria (usuario, accion, entidad, entidadid, detalle, ip, useragent)
     VALUES (:usuarioId, :accion, :entidad, :entidadId, CAST(:detalle AS jsonb), :ip, :userAgent)`,
    {
      usuarioId, accion, entidad, entidadId: entidadId ? String(entidadId) : null,
      detalle: aJson(detalle) || '{}',
      ip: ipDe(req),
      userAgent: req?.headers?.['user-agent'] ? String(req.headers['user-agent']).slice(0, 300) : null,
    },
  );
}

module.exports = { logError, logMensaje, auditar, limpiar };
