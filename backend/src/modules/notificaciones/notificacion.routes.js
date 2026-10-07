const express = require('express');
const router = express.Router();
const controller = require('./notificacion.controller');
const schema = require('./notificacion.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken } = require('../../middlewares/auth.middleware');

// Todas las rutas son del usuario autenticado: solo ve y modifica sus propias notificaciones.
router.use(verificarToken);

router.get('/', schema.listado, validar, controller.listar);
router.patch('/:id/leida', schema.id, validar, controller.marcarLeida);
router.post('/dispositivo', schema.dispositivo, validar, controller.registrarDispositivo);
router.delete('/dispositivo', schema.quitarDispositivo, validar, controller.quitarDispositivo);

module.exports = router;
