// Error de negocio con status HTTP. Se LANZA (throw) y el errorHandler lo convierte en respuesta.
//   throw AppError.conflict('El email ya está registrado', 'EMAILDUPLICADO');
//   throw new AppError('Espera 30 segundos', 429, 'ESPERA', { retryAfter: 30 });
class AppError extends Error {
  constructor(message, status = 500, code = 'ERRORINTERNO', extra = null) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
    this.extra = extra;        // campos adicionales que se agregan a la respuesta (p. ej. retryAfter)
  }

  static badRequest(msg = 'Solicitud inválida', code = 'SOLICITUDINVALIDA', extra) { return new AppError(msg, 400, code, extra); }
  static unauthorized(msg = 'No autenticado', code = 'NOAUTENTICADO', extra) { return new AppError(msg, 401, code, extra); }
  static forbidden(msg = 'No tiene permisos para esta acción', code = 'PROHIBIDO', extra) { return new AppError(msg, 403, code, extra); }
  static notFound(msg = 'Recurso no encontrado', code = 'NOENCONTRADO', extra) { return new AppError(msg, 404, code, extra); }
  static conflict(msg = 'Conflicto con el estado actual', code = 'CONFLICTO', extra) { return new AppError(msg, 409, code, extra); }
  static tooMany(msg = 'Demasiadas solicitudes', code = 'DEMASIADASSOLICITUDES', extra) { return new AppError(msg, 429, code, extra); }
}

module.exports = AppError;
