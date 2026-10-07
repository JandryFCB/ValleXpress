const asyncHandler = require('../../shared/helpers/asyncHandler');
const vendedorService = require('./vendedor.service');

// Controller delgado: recibe la petición, llama al servicio y responde. La lógica está en vendedor.service.js
// y las validaciones en vendedor.schema.js. Las respuestas conservan el formato que ya consume la app.

const listar = asyncHandler(async (req, res) => res.json(await vendedorService.listar(req)));

const obtenerPorId = asyncHandler(async (req, res) => res.json(await vendedorService.obtener(req.params.id, req)));

const miPerfil = asyncHandler(async (req, res) => res.json(await vendedorService.miPerfil(req.usuario.id, req)));

const crear = asyncHandler(async (req, res) => {
  const resultado = await vendedorService.crear(req.usuario.id, req.body, req);
  res.status(201).json({ message: 'Negocio creado exitosamente', ...resultado });
});

const actualizar = asyncHandler(async (req, res) => {
  const resultado = await vendedorService.actualizar(req.usuario.id, req.body, req);
  res.json({ message: 'Perfil actualizado exitosamente', ...resultado });
});

const eliminar = asyncHandler(async (req, res) => {
  await vendedorService.eliminar(req.usuario.id, req);
  res.json({ message: 'Negocio eliminado exitosamente' });
});

const actualizarUbicacion = asyncHandler(async (req, res) => {
  const ubicacion = await vendedorService.actualizarUbicacion(req.usuario.id, req.body.latitud, req.body.longitud);
  res.json({ message: 'Ubicación actualizada exitosamente', ubicacion });
});

const subirLogoPerfil = asyncHandler(async (req, res) => {
  const logo = await vendedorService.cambiarImagen(req.usuario.id, 'logo', req.body.logo, req);
  res.json({ message: 'Logo actualizado correctamente', logo });
});

const subirBanner = asyncHandler(async (req, res) => {
  const banner = await vendedorService.cambiarImagen(req.usuario.id, 'banner', req.body.banner, req);
  res.json({ message: 'Banner actualizado correctamente', banner });
});

module.exports = { listar, obtenerPorId, miPerfil, crear, actualizar, eliminar, actualizarUbicacion, subirLogoPerfil, subirBanner };
