const { validationResult } = require('express-validator');
const AppError = require('../errors/AppError');

// Se pone al final de la cadena de validaciones de una ruta:
//   router.post('/', [...reglas], validar, controller)
// Responde 400 con el PRIMER mensaje en "error" (lo que muestra la app) y la lista completa en "errors".
module.exports = (req, res, next) => {
  const resultado = validationResult(req);
  if (resultado.isEmpty()) return next();

  const detalles = resultado.array().map((e) => ({ campo: e.path, mensaje: e.msg }));
  const err = AppError.badRequest(detalles[0].mensaje, 'VALIDACIONFALLIDA');
  err.detalles = detalles;
  return next(err);
};
