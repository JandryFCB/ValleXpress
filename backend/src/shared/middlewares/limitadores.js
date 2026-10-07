const { rateLimit } = require('express-rate-limit');
const AppError = require('../errors/AppError');

// Límites de peticiones por IP. Al excederse responde 429 con el mismo formato que el resto de errores.
// Cada ruta sensible tiene SU PROPIO contador (un límite no gasta el cupo de otra ruta).
// (Detrás de Nginx/proxy hay que activar app.set('trust proxy', 1) para que la IP sea la del cliente.)
//
// LIMITES_DESACTIVADOS=true los apaga SOLO para pruebas automáticas locales; se ignora en producción.
const desactivados = () => process.env.LIMITES_DESACTIVADOS === 'true' && process.env.NODE_ENV !== 'production';

const crear = (windowMs, limit, mensaje) => rateLimit({
  windowMs,
  limit,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: desactivados,
  handler: (req, res, next, opciones) =>
    next(AppError.tooMany(mensaje, 'LIMITEEXCEDIDO', { retryAfter: Math.ceil(opciones.windowMs / 1000) })),
});

const MIN = 60 * 1000;

// Fábrica: cada llamada crea un contador nuevo e independiente
module.exports = {
  general: crear(MIN, 300, 'Demasiadas solicitudes. Intenta en un momento.'),
  login: () => crear(15 * MIN, 20, 'Demasiados intentos de inicio de sesión. Intenta en 15 minutos.'),
  registro: () => crear(60 * MIN, 10, 'Demasiados registros desde esta red. Intenta más tarde.'),
  consultas: () => crear(MIN, 40, 'Demasiadas consultas. Intenta en 1 minuto.'),
  enviarCodigo: () => crear(MIN, 5, 'Demasiadas solicitudes de código. Intenta en 1 minuto.'),
  verificarCodigo: () => crear(MIN, 10, 'Demasiados intentos. Intenta en 1 minuto.'),
  restablecer: () => crear(MIN, 5, 'Demasiados intentos. Intenta en 1 minuto.'),
};
