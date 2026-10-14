const express = require('express');
const controller = require('./negocios.controller');
const schema = require('./negocio.schema');
const productoSchema = require('../productos/producto.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// /api/mi-negocio: el negocio del vendedor autenticado y sus productos.
const router = express.Router();
router.use(verificarToken, verificarRol('vendedor'));

router.get('/', controller.miNegocio);
router.post('/', schema.crear, validar, controller.crear);
router.put('/', schema.actualizar, validar, controller.actualizar);
router.put('/local', schema.local, validar, controller.local);
router.put('/horarios', schema.horarios, validar, controller.horarios);
router.patch('/estado', schema.estado, validar, controller.estado);
router.put('/logo', schema.imagen, validar, controller.logo);
router.put('/portada', schema.imagen, validar, controller.portada);

router.get('/productos', controller.misProductos);
router.post('/productos', productoSchema.crear, validar, controller.crearProducto);
router.put('/productos/:id', productoSchema.actualizar, validar, controller.actualizarProducto);
router.patch('/productos/:id/estado', productoSchema.estado, validar, controller.estadoProducto);
router.patch('/productos/:id/stock', productoSchema.stock, validar, controller.stockProducto);
router.put('/productos/:id/imagen', productoSchema.imagen, validar, controller.imagenProducto);
router.delete('/productos/:id', productoSchema.id, validar, controller.eliminarProducto);

module.exports = router;
