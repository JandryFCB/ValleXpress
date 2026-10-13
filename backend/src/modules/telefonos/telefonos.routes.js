const express = require('express');
const router = express.Router();
const controller = require('./telefonos.controller');
const schema = require('./telefono.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken } = require('../../middlewares/auth.middleware');

// Todas las rutas son del usuario autenticado y solo ve/modifica sus propios teléfonos.
router.use(verificarToken);

router.get('/', controller.listar);
router.get('/tipos', controller.tipos);                                  // antes de /:id
router.post('/', schema.crear, validar, controller.crear);
router.put('/:id', schema.actualizar, validar, controller.actualizar);
router.patch('/:id/principal', schema.id, validar, controller.marcarPrincipal);
router.delete('/:id', schema.id, validar, controller.eliminar);

module.exports = router;
