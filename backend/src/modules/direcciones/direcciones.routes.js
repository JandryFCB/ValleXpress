const express = require('express');
const router = express.Router();
const controller = require('./direcciones.controller');
const schema = require('./direccion.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken } = require('../../middlewares/auth.middleware');

// Todas las rutas son del usuario autenticado y solo ve/modifica sus propias direcciones.
router.use(verificarToken);

router.get('/', controller.listar);
router.get('/predeterminada', controller.predeterminada);
router.get('/tipos', controller.tipos);
router.post('/', schema.crear, validar, controller.crear);
router.put('/:id', schema.actualizar, validar, controller.actualizar);
router.patch('/:id/predeterminada', schema.id, validar, controller.marcarPredeterminada);
router.delete('/:id', schema.id, validar, controller.eliminar);

module.exports = router;
