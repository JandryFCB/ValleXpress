const express = require('express');
const router = express.Router();
const notificacionController = require('../controllers/notificacion.controller');
const { verificarToken } = require('../middlewares/auth.middleware');

router.get('/', verificarToken, notificacionController.listar);
router.patch('/:id/leida', verificarToken, notificacionController.marcarLeida);

module.exports = router;
