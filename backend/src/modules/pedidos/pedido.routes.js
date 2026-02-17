const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const pedidoController = require('./pedido.controller');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');


// Repartidor marca pedido en camino
router.patch('/:id/en-camino',
  verificarToken,
  verificarRol('repartidor'),
  pedidoController.marcarEnCamino
);

// Repartidor marca pedido como recogido
router.patch('/:id/recogido',
  verificarToken,
  verificarRol('repartidor'),
  pedidoController.marcarRecogido
);

// Repartidor marca pedido entregado
router.patch('/:id/entregado',
  verificarToken,
  verificarRol('repartidor'),
  pedidoController.marcarEntregado
);


// Cliente marca pedido recibido
router.patch('/:id/recibido',
  verificarToken,
  verificarRol('cliente'),
  pedidoController.marcarRecibidoCliente
);
// Repartidor acepta pedido y asigna delivery
router.patch('/:id/aceptar-repartidor',
  verificarToken,
  verificarRol('repartidor'),
  body('costoDelivery').isFloat({ min: 0 }).withMessage('El costo de delivery es requerido y debe ser >= 0'),
  pedidoController.aceptarRepartidor
);

// Validaciones
const validacionCrear = [
  body('vendedorId')
    .notEmpty().withMessage('El vendedor es requerido')
    .isUUID().withMessage('ID de vendedor inválido'),
  body('productos')
    .isArray({ min: 1 }).withMessage('Debe incluir al menos un producto'),
  body('productos.*.productoId')
    .notEmpty().withMessage('ID del producto es requerido')
    .isUUID().withMessage('ID del producto inválido'),
  body('productos.*.cantidad')
    .isInt({ min: 1 }).withMessage('La cantidad debe ser al menos 1'),
  body('metodoPago')
    .notEmpty().withMessage('El método de pago es requerido')
];

const validacionEstado = [
  body('estado')
    .notEmpty().withMessage('El estado es requerido')
    .isIn(['confirmado', 'preparando', 'listo'])
    .withMessage('Estado inválido')
];


// Rutas protegidas
router.post('/',
  verificarToken,
  verificarRol('cliente'),
  validacionCrear,
  pedidoController.crear
);

router.get('/mis-pedidos',
  verificarToken,
  verificarRol('cliente'),
  pedidoController.misPedidos
);

router.get('/vendedor/pedidos',
  verificarToken,
  verificarRol('vendedor'),
  pedidoController.pedidosVendedor
);

router.get('/:id',
  verificarToken,
  pedidoController.obtenerPorId
);

router.put('/:id/estado',
  verificarToken,
  verificarRol('vendedor'),
  validacionEstado,
  pedidoController.actualizarEstado
);

router.put('/:id/cancelar',
  verificarToken,
  verificarRol('cliente'),
  pedidoController.cancelar
);

module.exports = router;
