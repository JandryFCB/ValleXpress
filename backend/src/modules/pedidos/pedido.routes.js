const express = require('express');
const router = express.Router();
const controller = require('./pedido.controller');
const schema = require('./pedido.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// /api/pedidos. Cada ruta lista, en orden: autenticación/rol -> reglas de validación -> validar -> controller.
// Los pedidos del negocio (vendedor) están en /api/mi-negocio/pedidos.
const cliente = [verificarToken, verificarRol('cliente')];

router.get('/metodos-pago', verificarToken, controller.metodosPago);
router.get('/cotizar', cliente, schema.cotizar, validar, controller.cotizar);
router.post('/', cliente, schema.crear, validar, controller.crear);
router.get('/mis-pedidos', cliente, schema.listado, validar, controller.misPedidos);
router.patch('/:id/cancelar', cliente, schema.cancelar, validar, controller.cancelar);
router.patch('/:id/recibido', cliente, schema.id, validar, controller.recibido);
router.post('/:id/calificar', cliente, schema.calificar, validar, controller.calificar);
router.post('/:id/comprobante', cliente, schema.comprobante, validar, controller.comprobante);

// Cualquier participante: el servicio comprueba que el pedido sea suyo (cliente, negocio o repartidor)
router.get('/:id', verificarToken, schema.id, validar, controller.obtener);

module.exports = router;
