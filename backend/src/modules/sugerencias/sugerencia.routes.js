const express = require('express');
const { body } = require('express-validator');
const validar = require('../../shared/middlewares/validar');
const asyncHandler = require('../../shared/helpers/asyncHandler');
const { verificarToken } = require('../../middlewares/auth.middleware');
const SugerenciaService = require('./sugerencia.service');

// /api/sugerencias: "Ayúdanos a mejorar ValleXpress" (cualquier usuario con sesión)
const router = express.Router();
router.use(verificarToken);

const nueva = [
  body('tipo').optional().toLowerCase().isIn(SugerenciaService.TIPOS).withMessage('Elige: sugerencia, problema o felicitación'),
  body('mensaje').isString().trim().isLength({ min: 10, max: 1000 }).withMessage('Cuéntanos un poco más (10 a 1000 letras)'),
  body('satisfaccion').optional({ values: 'null' }).isInt({ min: 1, max: 5 }).withMessage('La satisfacción va de 1 a 5').toInt(),
  body('versionApp').optional({ values: 'null' }).isString().isLength({ max: 20 }),
];

router.post('/', nueva, validar, asyncHandler(async (req, res) => res.status(201).json({ sugerencia: await SugerenciaService.crear(req.usuario, req.body, req) })));
router.get('/mias', asyncHandler(async (req, res) => res.json({ sugerencias: await SugerenciaService.mias(req.usuario.id) })));

module.exports = router;
