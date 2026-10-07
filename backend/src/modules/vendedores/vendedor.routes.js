const express = require('express');
const router = express.Router();
const controller = require('./vendedor.controller');
const schema = require('./vendedor.schema');
const validar = require('../../shared/middlewares/validar');
const { verificarToken, verificarRol } = require('../../middlewares/auth.middleware');

// Cada ruta lista, en orden: autenticación/rol -> reglas de validación -> validar -> controller.
const vendedor = [verificarToken, verificarRol('vendedor')];

// --- Rutas del propio vendedor (antes que /:id) ---
router.get('/perfil/mi-negocio', vendedor, controller.miPerfil);
router.put('/perfil/actualizar', vendedor, schema.actualizar, validar, controller.actualizar);
router.delete('/perfil/eliminar', vendedor, controller.eliminar);
router.patch('/perfil/ubicacion', vendedor, schema.ubicacion, validar, controller.actualizarUbicacion);
router.patch('/perfil/logo', vendedor, schema.logo, validar, controller.subirLogoPerfil);
router.patch('/perfil/banner', vendedor, schema.banner, validar, controller.subirBanner);

// --- Públicas (solo vendedores aprobados y activos) ---
router.get('/', controller.listar);
router.get('/:id', schema.id, validar, controller.obtenerPorId);

// --- Crear negocio (el registro ya lo crea; esto es por si falta) ---
router.post('/', vendedor, schema.crear, validar, controller.crear);

module.exports = router;
