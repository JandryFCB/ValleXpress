const express = require('express');
const controller = require('./repartidor.controller');
const schema = require('./repartidor.schema');
const validar = require('../../shared/middlewares/validar');
const { body, param } = require('express-validator');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// /api/repartidor: el repartidor autenticado, su perfil y sus entregas.
// La ubicación en vivo llega por socket ('repartidor:ubicacion'); PUT /ubicacion es el respaldo por HTTP.
const router = express.Router();
router.use(verificarToken, verificarRol('repartidor'));

router.get('/', controller.miPerfil);
router.post('/', schema.crear, validar, controller.crear);
router.put('/', schema.actualizar, validar, controller.actualizar);
router.post('/revision', controller.revision);
// Documentos para la verificación (cédula, selfie, licencia, matrícula): la foto llega en base64
router.get('/documentos', controller.documentos);
router.put('/documentos/:tipo', [param('tipo').isIn(require('./documentos.service').TIPOS).withMessage('Documento inválido'), body('imagen').isString().notEmpty().withMessage('Falta la foto del documento')], validar, controller.subirDocumento);
router.patch('/disponibilidad', schema.disponibilidad, validar, controller.disponibilidad);
// Lo que opinan de él clientes y negocios, y las advertencias del administrador
router.get('/reputacion', controller.reputacion);
router.put('/ubicacion', schema.ubicacion, validar, controller.ubicacion);

router.get('/pedidos/libres', controller.libres);
router.get('/pedidos', schema.listado, validar, controller.misEntregas);
router.patch('/pedidos/:id/aceptar', schema.id, validar, controller.aceptar);
router.patch('/pedidos/:id/recogido', schema.id, validar, controller.recoger);
router.patch('/pedidos/:id/entregado', schema.id, validar, controller.entregar);

module.exports = router;
