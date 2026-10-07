const express = require('express');
const router = express.Router();
const controller = require('./pedido.controller');
const schema = require('./pedido.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// Cada ruta lista, en orden: autenticación/rol -> reglas de validación -> validar -> controller.
const cliente = [verificarToken, verificarRol('cliente')];
const vendedor = [verificarToken, verificarRol('vendedor')];
const repartidor = [verificarToken, verificarRol('repartidor')];

// --- Cliente ---
router.post('/', cliente, schema.crear, validar, controller.crear);
router.get('/mis-pedidos', cliente, controller.misPedidos);
router.put('/:id/cancelar', cliente, schema.cancelar, validar, controller.cancelar);
router.patch('/:id/recibido', cliente, schema.id, validar, controller.marcarRecibidoCliente);
router.post('/:id/calificar', cliente, schema.calificar, validar, controller.calificar);

// --- Vendedor ---
router.get('/vendedor/pedidos', vendedor, controller.pedidosVendedor);
router.put('/:id/estado', vendedor, schema.estado, validar, controller.actualizarEstado);

// --- Repartidor ---
router.patch('/:id/aceptar-repartidor', repartidor, schema.aceptar, validar, controller.aceptarRepartidor);
router.patch('/:id/en-camino', repartidor, schema.id, validar, controller.marcarEnCamino);
router.patch('/:id/recogido', repartidor, schema.id, validar, controller.marcarRecogido);
router.patch('/:id/entregado', repartidor, schema.id, validar, controller.marcarEntregado);

// --- Cualquier participante: el servicio comprueba que el pedido sea suyo (cliente, vendedor o repartidor) ---
router.get('/:id', verificarToken, schema.id, validar, controller.obtenerPorId);

module.exports = router;
