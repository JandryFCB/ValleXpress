const express = require('express');
const controller = require('./negocios.controller');
const schema = require('./negocio.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken } = require('../../middlewares/auth.middleware');

// /api/negocios: lo que ve cualquier usuario autenticado (solo negocios aprobados).
const router = express.Router();
router.use(verificarToken);

router.get('/categorias', controller.categorias);                            // antes de /:id
router.get('/', schema.listar, validar, controller.listar);
router.get('/:id', schema.id, validar, controller.obtener);
router.get('/:id/productos', schema.id, validar, controller.menu);

module.exports = router;
