const { body, param, query } = require('express-validator');
const { APROBACIONAAPI, ESTADOPEDIDOAAPI, ROLAAPI, CATEGORIA } = require('../../shared/constants/codigos');
const { validarEmail, validarCedula, validarTelefono } = require('../../shared/utils/validators');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');

// Reglas de validación de /api/admin.
const APROBACIONES = Object.values(APROBACIONAAPI);
const ESTADOSPEDIDO = ['activos', 'historial', ...Object.values(ESTADOPEDIDOAAPI)];
const ROLES = Object.values(ROLAAPI);

const pagina = [
  query('page').optional().isInt({ min: 1 }).withMessage('Página inválida'),
  query('limit').optional().isInt({ min: 1, max: 50 }).withMessage('limit debe estar entre 1 y 50'),
  query('q').optional().isString().isLength({ max: 80 }).withMessage('Búsqueda demasiado larga'),
];
const motivo = body('motivo').optional({ values: 'null' }).isString().trim().isLength({ max: 300 }).withMessage('El motivo no puede pasar de 300 caracteres');

const listadoAprobacion = [...pagina, query('aprobacion').optional().isIn(APROBACIONES).withMessage(`aprobacion debe ser: ${APROBACIONES.join(', ')}`)];

const aprobacion = [body('estado').isIn(APROBACIONES).withMessage(`El estado debe ser: ${APROBACIONES.join(', ')}`), motivo];

const idNegocio = [param('id').isInt({ min: 1 }).withMessage('ID de negocio inválido').toInt()];
const idPedido = [param('id').isInt({ min: 1 }).withMessage('ID de pedido inválido').toInt()];
const usuario = [param('usuario').matches(/^[a-z0-9]{3,30}$/).withMessage('Usuario inválido')];

const listadoPedidos = [
  ...pagina,
  query('estado').optional().isIn(ESTADOSPEDIDO).withMessage('Estado de pedido inválido'),
  query('negocioId').optional().isInt({ min: 1 }).withMessage('negocioId inválido').toInt(),
];

const cancelarPedido = [
  ...idPedido,
  body('motivo').isString().trim().isLength({ min: 5, max: 250 }).withMessage('Escribe el motivo (5 a 250 caracteres): se les enviará al cliente y al negocio'),
];

const listadoUsuarios = [
  ...pagina,
  query('rol').optional().isIn(ROLES).withMessage(`rol debe ser: ${ROLES.join(', ')}`),
  query('activo').optional().isIn(['true', 'false']).withMessage('activo debe ser true o false'),
];

const estadoUsuario = [...usuario, body('activo').isBoolean().withMessage('activo debe ser true o false').toBoolean(), motivo];

const MSGTELEFONO = 'El teléfono debe tener 10 dígitos y empezar con 09 (ej: 0991234567)';
const clave = (campo) => body(campo).isString().withMessage('La contraseña es requerida').isLength({ min: 6, max: 72 }).withMessage('La contraseña debe tener entre 6 y 72 caracteres');
const datosPersona = (requerido) => {
  const opc = (r) => (requerido ? r : r.optional());
  return [
    opc(body('nombre')).isString().trim().isLength({ min: 2, max: 100 }).withMessage('El nombre debe tener entre 2 y 100 letras'),
    opc(body('apellido')).isString().trim().isLength({ min: 1, max: 100 }).withMessage('Escribe el apellido'),
    opc(body('email')).trim().customSanitizer(normalizarEmail).custom(validarEmail).withMessage('Formato de email inválido'),
    opc(body('cedula')).trim().custom(validarCedula).withMessage('Cédula inválida: verifica los 10 dígitos'),
    opc(body('telefono')).customSanitizer(normalizarTelefono).custom(validarTelefono).withMessage(MSGTELEFONO),
  ];
};

// Crear una cuenta de cualquier rol. Vendedor: con nombreNegocio nace su negocio. Repartidor: con vehículo, su perfil.
const crearUsuario = [
  ...datosPersona(true),
  clave('password'),
  body('rol').isIn(ROLES).withMessage(`rol debe ser: ${ROLES.join(', ')}`),
  body('nombreNegocio').if(body('rol').equals('vendedor')).isString().trim().isLength({ min: 2, max: 120 }).withMessage('Escribe el nombre del negocio'),
  body('categoriaNegocio').optional({ values: 'falsy' }).isIn(Object.values(CATEGORIA)).withMessage('Categoría de negocio inválida'),
  body('vehiculo').if(body('rol').equals('repartidor')).isString().isLength({ min: 2, max: 20 }).withMessage('Elige el vehículo'),
  body('placa').optional({ values: 'falsy' }).isString().isLength({ max: 12 }).withMessage('Placa inválida'),
  body('color').optional({ values: 'falsy' }).isString().isLength({ max: 30 }).withMessage('Color demasiado largo'),
];
const editarUsuario = [...usuario, ...datosPersona(false)];
const claveUsuario = [...usuario, clave('clave')];
const fotoUsuario = [...usuario, body('imagen').isString().withMessage('Envía la imagen').notEmpty().withMessage('Envía la imagen')];
const bajaUsuario = [...usuario, body('motivo').isString().trim().isLength({ min: 3, max: 300 }).withMessage('Escribe el motivo de la baja')];
const negocioGestion = [param('negocioId').isInt({ min: 1 }).withMessage('ID de negocio inválido')];
const editarRepartidor = [
  ...usuario,
  body('vehiculo').optional().customSanitizer((v) => String(v ?? '').trim().toLowerCase()),
  body('placa').optional({ values: 'null' }).isString().isLength({ max: 12 }).withMessage('Placa demasiado larga'),
  body('color').optional({ values: 'null' }).isString().isLength({ max: 30 }).withMessage('Color demasiado largo'),
];

const configuracion = [body('aprobacionAutomatica').isBoolean().withMessage('aprobacionAutomatica debe ser true o false').toBoolean()];

module.exports = {
  listadoAprobacion, aprobacion, idNegocio, usuario, listadoPedidos, idPedido, cancelarPedido, listadoUsuarios, estadoUsuario, configuracion,
  crearUsuario, editarUsuario, claveUsuario, fotoUsuario, bajaUsuario, negocioGestion, editarRepartidor,
};
