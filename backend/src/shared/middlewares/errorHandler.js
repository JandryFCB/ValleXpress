const AppError = require('../errors/AppError');
const { logError } = require('../services/log.service');

// Formato de error (compatible con la app Flutter actual, que lee "error" como texto):
//   { success:false, error:"mensaje", code:"CODIGOESTABLE", errors:[...]?, ...extra }

const ENPRODUCCION = () => process.env.NODE_ENV === 'production';

// Mensajes según la restricción UNIQUE que se violó (carreras entre dos registros simultáneos)
const MENSAJESUNICOS = {
  EMAIL: 'El email ya está registrado',
  DOC: 'La cédula ya está registrada',
  TELEFONO: 'El teléfono ya está registrado',
  NUMERO: 'El teléfono ya está registrado',
  PLACA: 'Esta placa ya está registrada por otro repartidor',
  RUC: 'El RUC ya está registrado',
};

function mensajeUnico(err) {
  const restriccion = String(err.parent?.constraint || err.original?.constraint || '').toUpperCase();
  const clave = Object.keys(MENSAJESUNICOS).find((k) => restriccion.endsWith(k));
  return clave ? MENSAJESUNICOS[clave] : 'El registro ya existe';
}

// 404 para rutas inexistentes
const notFoundHandler = (req, res, next) =>
  next(AppError.notFound('Ruta no encontrada', 'RUTANOENCONTRADA', { path: req.originalUrl }));

// Manejo global de errores. Debe registrarse al final de todas las rutas.
// eslint-disable-next-line no-unused-vars
const errorHandler = (err, req, res, next) => {
  let status = err.status || err.statusCode || 500;
  let code = err instanceof AppError ? err.code : 'ERRORINTERNO';
  let message = err.message;

  if (err.name === 'SequelizeUniqueConstraintError') { status = 409; code = 'DUPLICADO'; message = mensajeUnico(err); }
  else if (err.name === 'SequelizeValidationError') { status = 400; code = 'VALIDACIONFALLIDA'; message = err.errors?.[0]?.message || message; }
  else if (err.name === 'JsonWebTokenError') { status = 401; code = 'TOKENINVALIDO'; message = 'Token inválido'; }
  else if (err.name === 'TokenExpiredError') { status = 401; code = 'TOKENEXPIRADO'; message = 'Token expirado'; }
  else if (err.type === 'entity.too.large') { status = 413; code = 'SOLICITUDMUYGRANDE'; message = 'La solicitud es demasiado grande'; }
  else if (err.type === 'entity.parse.failed') { status = 400; code = 'JSONINVALIDO'; message = 'El cuerpo de la solicitud no es un JSON válido'; }
  else if (err.code === 'LIMIT_FILE_SIZE') { status = 400; code = 'ARCHIVOMUYGRANDE'; message = 'El archivo supera el tamaño permitido'; }

  // Errores 5xx inesperados: se guardan en LOGERRORES (sin esperar) y en producción no se expone el detalle.
  // El 501 ("no implementado") es deliberado y su mensaje es seguro: ni se registra como error ni se oculta.
  if (status >= 500 && status !== 501) {
    console.error('❌ Error:', err);
    logError(err, req, { estado: status });
    if (ENPRODUCCION()) message = 'Error interno del servidor';
  }

  return res.status(status).json({
    success: false,
    error: message,
    code,
    ...(err.detalles && { errors: err.detalles }),
    ...(err.extra || {}),
    ...(!ENPRODUCCION() && status >= 500 && { stack: err.stack }),
  });
};

module.exports = { notFoundHandler, errorHandler };
