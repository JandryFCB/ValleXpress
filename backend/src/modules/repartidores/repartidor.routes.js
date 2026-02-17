
const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const repartidorController = require('./repartidor.controller');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');
const upload = require('../../middlewares/upload.middleware');

// Subir foto de perfil del repartidor (base64)
router.patch('/perfil/foto',
  verificarToken,
  verificarRol('repartidor'),
  repartidorController.subirFotoPerfil
);

// Validaciones
const validacionCrear = [
  body('vehiculo')
    .notEmpty().withMessage('El vehículo es requerido'),
  body('placa')
    .notEmpty().withMessage('La placa es requerida'),
  body('licencia')
    .notEmpty().withMessage('La licencia es requerida')
];

const validacionUbicacion = [
  body('latitud')
    .notEmpty().withMessage('La latitud es requerida')
    .isFloat().withMessage('Latitud inválida'),
  body('longitud')
    .notEmpty().withMessage('La longitud es requerida')
    .isFloat().withMessage('Longitud inválida')
];

const validacionDisponibilidad = [
  body('disponible')
    .notEmpty().withMessage('El campo disponible es requerido')
    .isBoolean().withMessage('Debe ser true o false')
];

const validacionEstado = [
  body('estado')
    .notEmpty().withMessage('El estado es requerido')
    .isIn(['en_camino', 'entregado'])
    .withMessage('Estado no válido. Usa: en_camino o entregado')
];

const validacionAceptarPedido = [
  body('costoDelivery')
    .notEmpty().withMessage('El costo de delivery es requerido')
    .isFloat({ min: 0 }).withMessage('El costo de delivery debe ser mayor o igual a 0')
];

// Rutas públicas
router.get('/disponibles', repartidorController.listarDisponibles);

// Rutas protegidas (solo repartidores)
router.post('/', 
  verificarToken, 
  verificarRol('repartidor'), 
  validacionCrear, 
  repartidorController.crear
);

router.get('/perfil/mi-perfil', 
  verificarToken, 
  verificarRol('repartidor'), 
  repartidorController.miPerfil
);

router.put('/perfil/actualizar', 
  verificarToken, 
  verificarRol('repartidor'), 
  repartidorController.actualizar
);

router.put('/disponibilidad', 
  verificarToken, 
  verificarRol('repartidor'), 
  validacionDisponibilidad, 
  repartidorController.cambiarDisponibilidad
);

router.put('/ubicacion', 
  verificarToken, 
  verificarRol('repartidor'), 
  validacionUbicacion, 
  repartidorController.actualizarUbicacion
);

router.get('/mis-pedidos', 
  verificarToken, 
  verificarRol('repartidor'), 
  repartidorController.misPedidos
);

router.put('/pedidos/:id/estado',
  verificarToken,
  verificarRol('repartidor'),
  validacionEstado,
  repartidorController.actualizarEstadoPedido
);

// Aceptar pedido y asignar precio de delivery
router.post('/pedidos/:id/aceptar',
  verificarToken,
  verificarRol('repartidor'),
  validacionAceptarPedido,
  repartidorController.aceptarPedido
);

// Listar pedidos listos para entrega (no asignados)
router.get('/pendientes',
  verificarToken,
  verificarRol('repartidor'),
  repartidorController.pedidosPendientes
);

// Listar todos los pedidos aceptados por vendedores (para vista del repartidor)
router.get('/pedidos-vista',
  verificarToken,
  verificarRol('repartidor'),
  repartidorController.pedidosVista
);

// Obtener ubicación actual de un repartidor específico
router.get('/:id/ubicacion',
  verificarToken,
  repartidorController.obtenerUbicacion
);

// Ruta administrativa
router.get('/',
  verificarToken,
  repartidorController.listar
);

module.exports = router;
