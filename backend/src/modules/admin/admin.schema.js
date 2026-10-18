const { body, param, query } = require('express-validator');
const { APROBACIONAAPI, ESTADOPEDIDOAAPI, ROLAAPI, CATEGORIA } = require('../../shared/constants/codigos');
const { validarEmail, validarCedula, validarTelefono } = require('../../shared/utils/validators');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');
const { ROLESPERFIL } = require('../../shared/services/perfiles.service');
const { LIMITES } = require('../../shared/services/tarifas.service');
const { LIMITES: LIMITESZONA } = require('../../shared/services/zona.service');
const { TIPOSCUENTA } = require('../suscripciones/suscripcion.service');

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
  body('enviarCorreo').optional().isBoolean().withMessage('enviarCorreo debe ser true o false').toBoolean(),
];
const editarUsuario = [...usuario, ...datosPersona(false)];
const claveUsuario = [...usuario, clave('clave'), body('enviarCorreo').optional().isBoolean().toBoolean()];
const fotoUsuario = [...usuario, body('imagen').isString().withMessage('Envía la imagen').notEmpty().withMessage('Envía la imagen')];
const bajaUsuario = [...usuario, body('motivo').isString().trim().isLength({ min: 3, max: 300 }).withMessage('Escribe el motivo de la baja')];
const negocioGestion = [param('negocioId').isInt({ min: 1 }).withMessage('ID de negocio inválido')];
const editarRepartidor = [
  ...usuario,
  body('vehiculo').optional().customSanitizer((v) => String(v ?? '').trim().toLowerCase()),
  body('placa').optional({ values: 'null' }).isString().isLength({ max: 12 }).withMessage('Placa demasiado larga'),
  body('color').optional({ values: 'null' }).isString().isLength({ max: 30 }).withMessage('Color demasiado largo'),
];

// Tarifas: cada una opcional, dentro de sus límites (TarifasService.LIMITES); al menos una
const tarifas = [
  ...Object.entries(LIMITES).map(([campo, [min, max]]) => body(campo).optional().isFloat({ min, max }).withMessage(`${campo} debe estar entre ${min} y ${max}`).toFloat()),
  body().custom((b) => Object.keys(LIMITES).some((c) => b[c] !== undefined)).withMessage('Indica qué tarifa cambiar'),
];

// Zona de servicio: nombre y círculo (centro + radio); al menos un cambio
const zona = [
  body('nombre').optional().isString().trim().isLength({ min: 2, max: 60 }).withMessage('El nombre de la zona va de 2 a 60 letras'),
  ...Object.entries(LIMITESZONA).map(([campo, [min, max]]) => body(campo).optional().isFloat({ min, max }).withMessage(`${campo} debe estar entre ${min} y ${max}`).toFloat()),
  body().custom((b) => ['nombre', ...Object.keys(LIMITESZONA)].some((c) => b[c] !== undefined)).withMessage('Indica qué cambiar de la zona'),
];

// Suscripción mensual de vendedores y repartidores
const pagoSuscripcion = [
  body('mes').matches(/^\d{4}-\d{2}(-\d{2})?$/).withMessage('Indica el mes (AAAA-MM)')
    .customSanitizer((v) => (String(v).length === 7 ? `${v}-01` : v)),
  body('referencia').optional({ values: 'null' }).isString().trim().isLength({ max: 100 }).withMessage('La referencia es muy larga'),
];
const configSuscripciones = [
  body('cuotaVendedor').optional().isFloat({ min: 0, max: 500 }).withMessage('La cuota del vendedor va de $0 a $500').toFloat(),
  body('cuotaRepartidor').optional().isFloat({ min: 0, max: 500 }).withMessage('La cuota del repartidor va de $0 a $500').toFloat(),
  body('diasGracia').optional().isInt({ min: 1, max: 28 }).withMessage('El día límite para pagar va del 1 al 28').toInt(),
  body('inicio').optional().matches(/^\d{4}-\d{2}(-\d{2})?$/).withMessage('Indica desde qué mes se cobra (AAAA-MM)'),
  body('cuenta').optional().isObject().withMessage('Los datos de la cuenta van como objeto'),
  body('cuenta.banco').optional().isString().trim().isLength({ max: 60 }).withMessage('El nombre del banco es muy largo'),
  body('cuenta.tipo').optional().isIn(TIPOSCUENTA).withMessage(`El tipo de cuenta es ${TIPOSCUENTA.join(' o ')}`),
  body('cuenta.numero').optional().isString().trim().matches(/^[0-9-]{0,30}$/).withMessage('El número de cuenta lleva solo números'),
  body('cuenta.titular').optional().isString().trim().isLength({ max: 100 }).withMessage('El titular es muy largo'),
  body('cuenta.identificacion').optional().isString().trim().matches(/^(\d{10}|\d{13})?$/).withMessage('La cédula (10 dígitos) o el RUC (13) no son válidos'),
  body('cuenta.notas').optional().isString().trim().isLength({ max: 200 }).withMessage('Las notas son muy largas'),
  body().custom((b) => ['cuotaVendedor', 'cuotaRepartidor', 'diasGracia', 'inicio', 'cuenta'].some((c) => b[c] !== undefined)).withMessage('Indica qué cambiar'),
];
const idComprobante = [param('id').isInt({ min: 1 }).withMessage('Comprobante inválido').toInt()];
const advertencia = [body('motivo').isString().trim().isLength({ min: 10, max: 500 }).withMessage('Escribe el motivo de la advertencia (10 a 500 letras)')];
const rechazoComprobante = [body('motivo').isString().trim().isLength({ min: 5, max: 300 }).withMessage('Escribe el motivo del rechazo (5 a 300 letras)')];

// Permisos de un perfil: al menos un cambio; aprobarPendientes solo acompaña a la aprobación automática
const booleanoOpcional = (campo) => body(campo).optional().isBoolean().withMessage(`${campo} debe ser true o false`).toBoolean();
const perfil = [
  param('rol').isIn(ROLESPERFIL).withMessage(`El perfil debe ser: ${ROLESPERFIL.join(', ')}`),
  booleanoOpcional('registroAbierto'),
  booleanoOpcional('aprobacionAutomatica'),
  booleanoOpcional('aprobarPendientes'),
  body().custom((b) => b.registroAbierto !== undefined || b.aprobacionAutomatica !== undefined || b.aprobarPendientes === true)
    .withMessage('Indica qué permiso cambiar'),
];

module.exports = {
  listadoAprobacion, aprobacion, idNegocio, usuario, listadoPedidos, idPedido, cancelarPedido, listadoUsuarios, estadoUsuario, perfil, tarifas, zona, pagoSuscripcion, configSuscripciones, idComprobante, rechazoComprobante, advertencia,
  crearUsuario, editarUsuario, claveUsuario, fotoUsuario, bajaUsuario, negocioGestion, editarRepartidor,
};
