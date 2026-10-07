const express = require('express');
const router = express.Router();
const controller = require('./repartidor.controller');
const schema = require('./repartidor.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// Cada ruta lista, en orden: autenticación/rol -> reglas de validación -> validar -> controller.
const repartidor = [verificarToken, verificarRol('repartidor')];

// --- Perfil del propio repartidor ---
router.post('/', repartidor, schema.crear, validar, controller.crear);
router.get('/perfil/mi-perfil', repartidor, controller.miPerfil);
router.put('/perfil/actualizar', repartidor, schema.actualizar, validar, controller.actualizar);
router.patch('/perfil/foto', repartidor, schema.foto, validar, controller.subirFotoPerfil);

// --- Disponibilidad y ubicación ---
router.put('/disponibilidad', repartidor, schema.disponibilidad, validar, controller.cambiarDisponibilidad);
router.patch('/estado', repartidor, schema.estadoDisponibilidad, validar, controller.cambiarEstado);
router.put('/ubicacion', repartidor, schema.ubicacion, validar, controller.actualizarUbicacion);

// --- Pedidos desde el punto de vista del repartidor ---
router.get('/pendientes', repartidor, controller.pendientes);
router.get('/pedidos-disponibles', repartidor, controller.pendientes);          // nombre que usa la app: mismo resultado
router.get('/pedidos-vista', repartidor, controller.pedidosVista);
router.get('/mis-pedidos', repartidor, controller.misPedidos);
router.get('/entregas-activas', repartidor, controller.entregasActivas);
router.post('/pedidos/:id/aceptar', repartidor, schema.aceptar, validar, controller.aceptarPedido);
router.put('/pedidos/:id/estado', repartidor, schema.estadoPedido, validar, controller.actualizarEstadoPedido);

// --- Consultas de otros roles (antes eran públicas o abiertas a cualquier usuario) ---
router.get('/disponibles', verificarToken, verificarRol('vendedor', 'administrador'), controller.listarDisponibles);
router.get('/', verificarToken, verificarRol('administrador'), controller.listar);
// Solo el propio repartidor o el cliente/vendedor de una entrega suya en curso (el servicio lo comprueba)
router.get('/:id/ubicacion', verificarToken, schema.ubicacionDe, validar, controller.obtenerUbicacion);

module.exports = router;
