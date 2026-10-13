const { body, param } = require('express-validator');
const { validarTelefono } = require('../../shared/utils/validators');
const { normalizarTelefono } = require('../../shared/utils/normalizers');
const { TIPOSTELEFONO } = require('../../shared/constants/codigos');

// Reglas de validación de las rutas de teléfonos.
const ID = [param('id').isInt({ min: 1 }).withMessage('ID de teléfono inválido')];
const MSGTELEFONO = 'El teléfono debe tener 10 dígitos y empezar con 09 (ej: 0991234567)';
const TIPO = body('tipo').optional().customSanitizer((v) => String(v).trim().toUpperCase())
  .isIn(TIPOSTELEFONO).withMessage(`El tipo debe ser uno de: ${TIPOSTELEFONO.join(', ')}`);
const PRINCIPAL = body('principal').optional().isBoolean().withMessage('principal debe ser true o false');

const crear = [
  body('numero').customSanitizer(normalizarTelefono).custom(validarTelefono).withMessage(MSGTELEFONO),
  TIPO, PRINCIPAL,
];

const actualizar = [
  ...ID,
  body('numero').optional().customSanitizer(normalizarTelefono).custom(validarTelefono).withMessage(MSGTELEFONO),
  TIPO, PRINCIPAL,
];

module.exports = { id: ID, crear, actualizar };
