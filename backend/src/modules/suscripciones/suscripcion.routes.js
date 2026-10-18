const express = require('express');
const { body } = require('express-validator');
const validar = require('../../shared/middlewares/validar');
const asyncHandler = require('../../shared/helpers/asyncHandler');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');
const SuscripcionService = require('./suscripcion.service');

// /api/suscripcion: la cuota mensual del vendedor o el repartidor (su estado de cuenta y subir el comprobante)
const router = express.Router();
router.use(verificarToken, verificarRol('vendedor', 'repartidor'));

const comprobante = [
  body('mes').matches(/^\d{4}-\d{2}(-\d{2})?$/).withMessage('Indica el mes que pagas (AAAA-MM)'),
  body('imagen').isString().withMessage('Adjunta la foto del comprobante').notEmpty().withMessage('Adjunta la foto del comprobante'),
  body('referencia').optional({ values: 'null' }).isString().trim().isLength({ max: 100 }).withMessage('La referencia es muy larga'),
];

router.get('/', asyncHandler(async (req, res) => res.json(await SuscripcionService.estado(req.usuario.id, req))));
router.post('/comprobante', comprobante, validar, asyncHandler(async (req, res) => {
  const mes = String(req.body.mes).length === 7 ? `${req.body.mes}-01` : req.body.mes;
  res.status(201).json(await SuscripcionService.subirComprobante(req.usuario, { ...req.body, mes }, req));
}));

module.exports = router;
