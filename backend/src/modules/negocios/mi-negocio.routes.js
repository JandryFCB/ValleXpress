const express = require('express');
const controller = require('./negocios.controller');
const schema = require('./negocio.schema');
const productoSchema = require('../productos/producto.schema');
const pedidoController = require('../pedidos/pedido.controller');
const pedidoSchema = require('../pedidos/pedido.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// Rutas de gestión de UN negocio: sus datos, local, horario, estado, imágenes y productos. Las usan el vendedor
// (/api/mi-negocio) y el administrador (/api/admin/negocios/:negocioId/gestion), que actúa como el dueño.
function rutasDeGestion(router) {
  router.get('/', controller.miNegocio);
  router.put('/', schema.actualizar, validar, controller.actualizar);
  router.put('/local', schema.local, validar, controller.local);
  router.put('/horarios', schema.horarios, validar, controller.horarios);
  router.patch('/estado', schema.estado, validar, controller.estado);
  router.put('/logo', schema.imagen, validar, controller.logo);
  router.put('/portada', schema.imagen, validar, controller.portada);
  router.get('/cuentas', controller.cuentas);
  router.put('/cuentas', schema.cuentas, validar, controller.fijarCuentas);

  router.get('/productos', controller.misProductos);
  router.post('/productos', productoSchema.crear, validar, controller.crearProducto);
  router.put('/productos/:id', productoSchema.actualizar, validar, controller.actualizarProducto);
  router.patch('/productos/:id/estado', productoSchema.estado, validar, controller.estadoProducto);
  router.patch('/productos/:id/stock', productoSchema.stock, validar, controller.stockProducto);
  router.put('/productos/:id/imagen', productoSchema.imagen, validar, controller.imagenProducto);
  router.delete('/productos/:id', productoSchema.id, validar, controller.eliminarProducto);
  return router;
}

// /api/mi-negocio: el negocio del vendedor autenticado, sus productos y los pedidos que recibe.
const router = express.Router();
router.use(verificarToken, verificarRol('vendedor'));
router.post('/', schema.crear, validar, controller.crear);
router.post('/revision', controller.revision);
rutasDeGestion(router);

// Pedidos que recibe el negocio
router.get('/pedidos', pedidoSchema.listado, validar, pedidoController.delNegocio);
router.patch('/pedidos/:id/estado', pedidoSchema.estadoNegocio, validar, pedidoController.estadoNegocio);
router.post('/pedidos/:id/pago', pedidoSchema.pago, validar, pedidoController.pagoNegocio);
router.post('/pedidos/:id/calificar-repartidor', pedidoSchema.calificar, validar, pedidoController.calificarRepartidor);

module.exports = router;
module.exports.rutasDeGestion = rutasDeGestion;
