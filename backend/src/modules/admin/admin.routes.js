const express = require('express');
const controller = require('./admin.controller');
const schema = require('./admin.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');
const { rutasDeGestion } = require('../negocios/mi-negocio.routes');

// /api/admin: panel del administrador (solo rol administrador).
const router = express.Router();
router.use(verificarToken, verificarRol('administrador'));

router.get('/resumen', controller.resumen);
router.get('/resumen/:tipo', controller.detalleCifra);

router.get('/negocios', schema.listadoAprobacion, validar, controller.negocios);
router.patch('/negocios/:id/aprobacion', schema.idNegocio, schema.aprobacion, validar, controller.aprobacionNegocio);

// Gestionar un negocio como su dueño: las mismas rutas de /api/mi-negocio (datos, local, horario, estado,
// logo, portada y productos) bajo /api/admin/negocios/:negocioId/gestion
const gestion = express.Router({ mergeParams: true });
gestion.use(controller.resolverDueno);
router.use('/negocios/:negocioId/gestion', schema.negocioGestion, validar, rutasDeGestion(gestion));

router.get('/repartidores', schema.listadoAprobacion, validar, controller.repartidores);
router.patch('/repartidores/:usuario/aprobacion', schema.usuario, schema.aprobacion, validar, controller.aprobacionRepartidor);
router.put('/repartidores/:usuario', schema.editarRepartidor, validar, controller.editarRepartidor);
router.get('/repartidores/:usuario/documentos', schema.usuario, validar, controller.documentosRepartidor);
router.get('/repartidores/:usuario/reputacion', schema.usuario, validar, controller.reputacionRepartidor);
router.post('/repartidores/:usuario/advertencias', schema.usuario, schema.advertencia, validar, controller.advertirRepartidor);

router.get('/pedidos', schema.listadoPedidos, validar, controller.pedidos);
router.get('/pedidos/:id', schema.idPedido, validar, controller.pedido);
router.patch('/pedidos/:id/cancelar', schema.cancelarPedido, validar, controller.cancelarPedido);

router.get('/usuarios', schema.listadoUsuarios, validar, controller.usuarios);
router.post('/usuarios', schema.crearUsuario, validar, controller.crearUsuario);
router.get('/usuarios/:usuario', schema.usuario, validar, controller.usuario);
router.put('/usuarios/:usuario', schema.editarUsuario, validar, controller.editarUsuario);
router.put('/usuarios/:usuario/clave', schema.claveUsuario, validar, controller.claveUsuario);
router.put('/usuarios/:usuario/foto', schema.fotoUsuario, validar, controller.fotoUsuario);
router.patch('/usuarios/:usuario/estado', schema.estadoUsuario, validar, controller.estadoUsuario);
router.post('/usuarios/:usuario/desbloquear', schema.usuario, validar, controller.quitarBloqueoTemporal);
router.delete('/usuarios/:usuario', schema.bajaUsuario, validar, controller.bajaUsuario);

router.get('/tarifas', controller.tarifas);
router.put('/tarifas', schema.tarifas, validar, controller.cambiarTarifas);
router.get('/legal', controller.legal);
// Sugerencias de clientes, vendedores y repartidores
router.get('/sugerencias', controller.sugerencias);
router.patch('/sugerencias/:id', schema.atenderSugerencia, validar, controller.atenderSugerencia);
// Suscripción mensual: quiénes pagan, comprobantes por revisar, pagos a mano y la configuración del cobro
router.get('/suscripciones', controller.suscripciones);
router.put('/suscripciones/config', schema.configSuscripciones, validar, controller.configSuscripciones);
router.get('/suscripciones/:usuario', schema.usuario, validar, controller.suscripcionDe);
router.post('/suscripciones/:usuario/pagos', schema.usuario, schema.pagoSuscripcion, validar, controller.registrarSuscripcion);
router.post('/comprobantes/:id/aprobar', schema.idComprobante, validar, controller.aprobarComprobante);
router.post('/comprobantes/:id/rechazar', schema.idComprobante, schema.rechazoComprobante, validar, controller.rechazarComprobante);
router.get('/zona', controller.zona);
router.put('/zona', schema.zona, validar, controller.cambiarZona);
router.get('/perfiles', controller.perfiles);
router.patch('/perfiles/:rol', schema.perfil, validar, controller.cambiarPerfil);
router.get('/soporte', controller.soporte);
router.put('/soporte', schema.soporte, validar, controller.cambiarSoporte);

module.exports = router;
