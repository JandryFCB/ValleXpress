const express = require('express');
const { body, param } = require('express-validator');
const LegalService = require('./legal.service');
const asyncHandler = require('../../shared/helpers/asyncHandler');
const validar = require('../../shared/middlewares/validar');
const { verificarToken } = require('../../middlewares/auth.middleware');

// API de documentos legales para la app:
//   GET  /api/legal              lista (título, versión, vigencia)                     pública
//   GET  /api/legal/pendientes   lo que el usuario debe aceptar (versión nueva)       con sesión
//   POST /api/legal/aceptar      { documentos: [{ id, version }] }                     con sesión
//   GET  /api/legal/:id          el documento en bloques listos para dibujar            pública
const router = express.Router();

router.get('/', (req, res) => res.json({ documentos: LegalService.lista() }));

router.get('/pendientes', verificarToken, asyncHandler(async (req, res) => res.json({ pendientes: await LegalService.pendientes(req.usuario) })));

router.post(
  '/aceptar',
  verificarToken,
  [
    body('documentos').isArray({ min: 1, max: 4 }).withMessage('Indica qué documentos aceptas'),
    body('documentos.*.id').isIn(LegalService.IDS).withMessage('Documento inválido'),
    body('documentos.*.version').isString().trim().notEmpty().withMessage('Falta la versión del documento'),
  ],
  validar,
  asyncHandler(async (req, res) => res.json({ pendientes: await LegalService.aceptar(req.usuario, req.body.documentos, req) })),
);

router.get('/:id', [param('id').isIn(LegalService.IDS).withMessage('Ese documento no existe')], validar, asyncHandler(async (req, res) => res.json({ documento: await LegalService.documento(req.params.id) })));

module.exports = router;
