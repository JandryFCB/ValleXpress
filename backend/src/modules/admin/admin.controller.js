const SuscripcionService = require('../suscripciones/suscripcion.service');
const LegalService = require('../legal/legal.service');
const asyncHandler = require('../../shared/helpers/asyncHandler');
const service = require('./admin.service');
const PedidoService = require('../pedidos/pedido.service');

// Controller delgado: la lógica del panel está en admin.service.js; la de los pedidos, en pedido.service.js.
const id = (req) => Number(req.params.id);

const resumen = asyncHandler(async (req, res) => res.json(await service.resumen()));

const negocios = asyncHandler(async (req, res) => res.json(await service.negocios(req.query, req)));
const aprobacionNegocio = asyncHandler(async (req, res) => res.json({ negocio: await service.cambiarAprobacionNegocio(req.usuario, id(req), req.body, req) }));

const repartidores = asyncHandler(async (req, res) => res.json(await service.repartidores(req.query)));
const aprobacionRepartidor = asyncHandler(async (req, res) =>
  res.json({ repartidor: await service.cambiarAprobacionRepartidor(req.usuario, req.params.usuario, req.body, req) }));

const pedidos = asyncHandler(async (req, res) => res.json(await PedidoService.listarTodos(req.query, req)));
const pedido = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.obtener(req.usuario, id(req), req) }));
const cancelarPedido = asyncHandler(async (req, res) => res.json({ pedido: await PedidoService.cancelarComoAdmin(req.usuario, id(req), req.body, req) }));

const usuarios = asyncHandler(async (req, res) => res.json(await service.usuarios(req.query, req)));
const estadoUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.cambiarEstadoUsuario(req.usuario, req.params.usuario, req.body, req) }));

const usuario = asyncHandler(async (req, res) => res.json({ usuario: await service.obtenerUsuario(req.params.usuario, req) }));
const crearUsuario = asyncHandler(async (req, res) => res.status(201).json({ usuario: await service.crearUsuario(req.usuario, req.body, req) }));
const editarUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.editarUsuario(req.usuario, req.params.usuario, req.body, req) }));
const claveUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.ponerClave(req.usuario, req.params.usuario, req.body.clave, req, { enviarCorreo: req.body.enviarCorreo !== false }) }));
const fotoUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.fotoUsuario(req.usuario, req.params.usuario, req.body.imagen, req) }));
const bajaUsuario = asyncHandler(async (req, res) => res.json({ usuario: await service.darDeBaja(req.usuario, req.params.usuario, req.body, req) }));
const editarRepartidor = asyncHandler(async (req, res) => res.json({ repartidor: await service.editarRepartidor(req.usuario, req.params.usuario, req.body, req) }));
const resolverDueno = asyncHandler(async (req, res, next) => { await service.resolverDueno(req); next(); });

const tarifas = asyncHandler(async (req, res) => res.json({ tarifas: await service.tarifas() }));
const cambiarTarifas = asyncHandler(async (req, res) => res.json({ tarifas: await service.cambiarTarifas(req.usuario, req.body, req) }));
const suscripciones = asyncHandler(async (req, res) => res.json(await SuscripcionService.resumen(req)));
const suscripcionDe = asyncHandler(async (req, res) => res.json(await SuscripcionService.estado(req.params.usuario, req)));
const aprobarComprobante = asyncHandler(async (req, res) => res.json(await SuscripcionService.aprobar(req.usuario, Number(req.params.id), req)));
const rechazarComprobante = asyncHandler(async (req, res) => res.json(await SuscripcionService.rechazar(req.usuario, Number(req.params.id), req.body, req)));
const registrarSuscripcion = asyncHandler(async (req, res) => res.status(201).json(await SuscripcionService.registrarPago(req.usuario, req.params.usuario, req.body, req)));
const configSuscripciones = asyncHandler(async (req, res) => res.json({ config: await service.cambiarConfigSuscripciones(req.usuario, req.body, req) }));
const zona = asyncHandler(async (req, res) => res.json({ zona: await service.zona() }));
const cambiarZona = asyncHandler(async (req, res) => res.json({ zona: await service.cambiarZona(req.usuario, req.body, req) }));
const perfiles = asyncHandler(async (req, res) => res.json({ perfiles: await service.perfiles() }));
const cambiarPerfil = asyncHandler(async (req, res) => res.json(await service.cambiarPerfil(req.usuario, req.params.rol, req.body, req)));

const legal = asyncHandler(async (req, res) => res.json({ documentos: await LegalService.estadisticas() }));

const detalleCifra = asyncHandler(async (req, res) => res.json(await service.detalleCifra(req.params.tipo, req.query.rango)));

const reputacionRepartidor = asyncHandler(async (req, res) => res.json(await require('../repartidores/reputacion.service').reputacion(req.params.usuario, { completo: true })));
const advertirRepartidor = asyncHandler(async (req, res) => res.status(201).json(await require('../repartidores/reputacion.service').advertir(req.usuario, req.params.usuario, req.body, req)));

const documentosRepartidor = asyncHandler(async (req, res) => res.json(await require('../repartidores/documentos.service').documentos(req.params.usuario, req)));

module.exports = { reputacionRepartidor, advertirRepartidor, documentosRepartidor, detalleCifra, legal, resumen, negocios, aprobacionNegocio, repartidores, aprobacionRepartidor, pedidos, pedido, cancelarPedido, usuarios, estadoUsuario, perfiles, cambiarPerfil, tarifas, cambiarTarifas, zona, cambiarZona,
  suscripciones, suscripcionDe, registrarSuscripcion, configSuscripciones, aprobarComprobante, rechazarComprobante,
  usuario, crearUsuario, editarUsuario, claveUsuario, fotoUsuario, bajaUsuario, editarRepartidor, resolverDueno };
