const express = require('express');
const router = express.Router();
const controller = require('./producto.controller');
const schema = require('./producto.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// Cada ruta lista, en orden: autenticación/rol -> reglas de validación -> validar -> controller.
const vendedor = [verificarToken, verificarRol('vendedor')];

// --- Públicas (solo productos de vendedores aprobados). Las rutas fijas van antes que /:id ---
router.get('/', schema.paginacion, validar, controller.listar);
router.get('/vendedor/:vendedorId', schema.vendedorId, validar, controller.listarPorVendedor);

// --- Del vendedor autenticado ---
router.get('/mis-productos', vendedor, controller.misProductos);
router.post('/', vendedor, schema.crear, validar, controller.crear);
router.patch('/:id/disponible', vendedor, schema.disponible, validar, controller.cambiarDisponible);
router.put('/:id', vendedor, schema.id, schema.actualizar, validar, controller.actualizar);
router.delete('/:id', vendedor, schema.id, validar, controller.eliminar);

// --- Pública: SIEMPRE al final ---
router.get('/:id', schema.id, validar, controller.obtenerPorId);

module.exports = router;
