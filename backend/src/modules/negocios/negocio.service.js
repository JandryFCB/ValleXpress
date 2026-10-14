const { Op } = require('sequelize');
const { Negocio, NegocioEstado, Horario } = require('./negocio.model');
const Direccion = require('../direcciones/direccion.model');
const Usuario = require('../auth/usuario.model');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const CatalogoService = require('../../shared/services/catalogo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { auditar } = require('../../shared/services/log.service');
const { APROBACION, APROBACIONAAPI, CATEGORIA, TIPODIRECCION } = require('../../shared/constants/codigos');

// Lógica de negocio de los NEGOCIOS (tiendas). Público: solo se ven los aprobados. El dueño (rol vendedor) ve y
// edita el suyo aunque esté pendiente. Cada cambio queda en el historial (FDESDE/FHASTA) con quién lo hizo.

const num = (v) => (v === null || v === undefined ? null : Number(v));
const hhmm = (t) => (t ? String(t).slice(0, 5) : null);                    // '08:00:00' -> '08:00'
const minutos = (t) => (t ? Number(String(t).slice(0, 2)) * 60 + Number(String(t).slice(3, 5)) : null);
const noEncontrado = () => AppError.notFound('Negocio no encontrado', 'NEGOCIONOENCONTRADO');

const INCLUIR = [
  { model: NegocioEstado, as: 'estado' },
  { model: Horario, as: 'horarios', required: false },
  { model: Direccion, as: 'local', required: false },
];

// Día (1 = lunes ... 7 = domingo) y minutos del día en Ecuador (UTC-5, sin horario de verano)
function ahoraEnEcuador() {
  const d = new Date(Date.now() - 5 * 60 * 60 * 1000);
  const dia = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  return { dia, minutos: d.getUTCHours() * 60 + d.getUTCMinutes() };
}

// ¿El horario de hoy incluye este momento? Sin horarios cargados no se restringe (manda el interruptor del vendedor).
// Si el cierre es menor que la apertura, el horario cruza la medianoche (ej. 18:00 a 02:00).
function dentroDeHorario(horarios = []) {
  if (!horarios.length) return true;
  const { dia, minutos: ahora } = ahoraEnEcuador();
  const hoy = horarios.find((h) => h.dia === dia);
  if (!hoy || hoy.cerrado) return false;
  const a = minutos(hoy.apertura);
  const c = minutos(hoy.cierre);
  return a < c ? ahora >= a && ahora < c : ahora >= a || ahora < c;
}

let cacheCategorias = null;
async function mapaCategorias() {
  if (!cacheCategorias) {
    const lista = await CatalogoService.tipos('tcategoriasnegocio', 'ccategorianegocio', {});
    cacheCategorias = Object.fromEntries(lista.map((c) => [c.codigo, c.descripcion]));
  }
  return cacheCategorias;
}

// Formato que recibe la app. "privado" agrega lo que solo ve el dueño (RUC, aprobación).
async function aApi(entrada, req, { privado = false } = {}) {
  const lista = Array.isArray(entrada) ? entrada : [entrada];
  const urls = await ArchivoService.mapaUrls(req, lista.flatMap((n) => [n.logoId, n.portadaId]));
  const categorias = await mapaCategorias();
  const salida = lista.map((n) => {
    const horarios = (n.horarios || [])
      .map((h) => ({ dia: h.dia, cerrado: h.cerrado, apertura: hhmm(h.apertura), cierre: hhmm(h.cierre) }))
      .sort((a, b) => a.dia - b.dia);
    const e = n.estado || {};
    return {
      id: Number(n.id),
      nombre: n.nombre,
      descripcion: n.descripcion,
      categoria: { codigo: n.categoria, descripcion: categorias[n.categoria] || 'Otros' },
      logo: urls[String(n.logoId)]?.url || null,
      portada: urls[String(n.portadaId)]?.url || null,
      costoEnvio: num(n.costoEnvio),
      pedidoMinimo: num(n.pedidoMinimo),
      tiempoPreparacion: n.tiempoPreparacion,
      radioKm: num(n.radioKm),
      abierto: e.abierto === true,
      abiertoAhora: e.abierto === true && dentroDeHorario(horarios),
      aceptaPedidos: e.aceptaPedidos !== false,
      calificacion: num(e.calificacion) ?? 0,
      numeroCalificaciones: e.numeroCalificaciones ?? 0,
      numeroPedidos: e.numeroPedidos ?? 0,
      local: n.local
        ? { id: Number(n.local.id), direccion: n.local.direccion, referencia: n.local.referencia, latitud: num(n.local.latitud), longitud: num(n.local.longitud) }
        : null,
      horarios,
      ...(privado && { ruc: n.ruc, aprobacion: APROBACIONAAPI[n.aprobacion], duenoId: n.duenoId }),
    };
  });
  return Array.isArray(entrada) ? salida : salida[0];
}

// ---------------------------------------------------------------------------------------------
// Público
// ---------------------------------------------------------------------------------------------
const categorias = async () => Object.entries(await mapaCategorias()).map(([codigo, descripcion]) => ({ codigo, descripcion }));

async function listar(query, req) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(50, Math.max(1, parseInt(query.limit, 10) || 20));
  const where = { aprobacion: APROBACION.APROBADO };
  if (query.categoria) where.categoria = query.categoria;
  if (query.q) {
    const texto = `%${String(query.q).trim().replace(/[%_]/g, '\\$&')}%`;
    where[Op.or] = [{ nombre: { [Op.iLike]: texto } }, { descripcion: { [Op.iLike]: texto } }];
  }
  if (query.abiertos === 'true') where['$estado.estaabierto$'] = true;

  // Sin los horarios en la consulta: son 7 filas por negocio y el LIMIT cortaría por filas, no por negocios
  const { count, rows } = await Negocio.findAndCountAll({
    where,
    include: INCLUIR.filter((i) => i.as !== 'horarios'),
    distinct: true,
    subQuery: false,
    order: [[{ model: NegocioEstado, as: 'estado' }, 'abierto', 'DESC'], [{ model: NegocioEstado, as: 'estado' }, 'calificacion', 'DESC'], ['nombre', 'ASC']],
    limit,
    offset: (page - 1) * limit,
  });
  const horarios = rows.length ? await Horario.findAll({ where: { negocioId: rows.map((r) => r.id) } }) : [];
  for (const r of rows) r.horarios = horarios.filter((h) => String(h.negocioId) === String(r.id));
  return {
    negocios: await aApi(rows, req),
    pagination: { page, limit, total: count, totalPages: Math.ceil(count / limit), hasNext: page * limit < count },
  };
}

// Un negocio aprobado lo ve cualquiera; uno pendiente solo su dueño. Cualquier otro caso: 404 (no se revela que existe).
async function obtener(id, usuario, req) {
  const n = await Negocio.findOne({ where: { id }, include: INCLUIR });
  const esDueno = n && n.duenoId === usuario.id;
  if (!n || (n.aprobacion !== APROBACION.APROBADO && !esDueno)) throw noEncontrado();
  return aApi(n, req, { privado: esDueno });
}

// ---------------------------------------------------------------------------------------------
// Dueño (vendedor)
// ---------------------------------------------------------------------------------------------
// El negocio del vendedor (hoy uno por vendedor; el modelo ya permite más)
const delDueno = (usuarioId, opciones = {}) => Negocio.findOne({ where: { duenoId: usuarioId }, order: [['id', 'ASC']], ...opciones });

async function exigirMio(usuarioId, opciones = {}) {
  const n = await delDueno(usuarioId, opciones);
  if (!n) throw AppError.notFound('Aún no tienes un negocio registrado', 'NEGOCIONOENCONTRADO');
  return n;
}

async function miNegocio(usuarioId, req) {
  const n = await exigirMio(usuarioId);
  const completo = await Negocio.findOne({ where: { id: n.id }, include: INCLUIR });
  return aApi(completo, req, { privado: true });
}

const categoriaValida = (c) => Object.values(CATEGORIA).includes(c);

// Crea el negocio de un vendedor (también se usa en el registro, dentro de su transacción).
// Mientras no exista el panel de administración, nace aprobado si APROBACIONAUTOMATICA está activa.
async function crearParaUsuario(usuarioId, datos, opciones = {}) {
  const automatica = (await ConfiguracionService.obtener('APROBACIONAUTOMATICA', true)) === true;
  return Negocio.create({
    duenoId: usuarioId,
    nombre: String(datos.nombre).trim(),
    descripcion: datos.descripcion?.trim() || null,
    categoria: categoriaValida(datos.categoria) ? datos.categoria : CATEGORIA.OTROS,
    aprobacion: automatica ? APROBACION.APROBADO : APROBACION.PENDIENTE,
    aprobadoEn: automatica ? new Date() : null,
  }, opciones);
}

async function crear(usuarioId, datos, req) {
  if (await delDueno(usuarioId)) throw AppError.conflict('Ya tienes un negocio registrado', 'YATIENENEGOCIO');
  const n = await withTransaction((t) => crearParaUsuario(usuarioId, datos, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'NEGOCIOCREADO', entidad: 'NEGOCIOS', entidadId: n.id, req });
  return miNegocio(usuarioId, req);
}

async function actualizar(usuarioId, datos, req) {
  const n = await exigirMio(usuarioId);
  const cambios = {};
  for (const campo of ['nombre', 'descripcion', 'costoEnvio', 'pedidoMinimo', 'tiempoPreparacion', 'radioKm']) {
    if (datos[campo] !== undefined) cambios[campo] = typeof datos[campo] === 'string' ? datos[campo].trim() || null : datos[campo];
  }
  if (datos.categoria !== undefined) {
    if (!categoriaValida(datos.categoria)) throw AppError.badRequest('Categoría inválida', 'CATEGORIAINVALIDA');
    cambios.categoria = datos.categoria;
  }
  if (datos.ruc !== undefined) cambios.ruc = String(datos.ruc || '').trim() || null;
  if (cambios.nombre === null) throw AppError.badRequest('El nombre del negocio es requerido', 'NOMBREREQUERIDO');
  await withTransaction((t) => n.update(cambios, { transaction: t }), { usuarioId });
  return miNegocio(usuarioId, req);
}

// El local es una dirección (tipo 005) de la persona dueña. Si ya había uno, se actualiza (queda en el historial).
async function fijarLocal(usuarioId, datos, req) {
  const n = await exigirMio(usuarioId);
  const dueno = await Usuario.findByPk(usuarioId, { attributes: ['id', 'personaId'] });
  await withTransaction(async (t) => {
    const valores = {
      direccion: datos.direccion.trim(),
      referencia: datos.referencia?.trim() || null,
      latitud: datos.latitud,
      longitud: datos.longitud,
    };
    const actual = n.direccionId ? await Direccion.findOne({ where: { id: n.direccionId }, transaction: t }) : null;
    if (actual) {
      await actual.update(valores, { transaction: t });
    } else {
      const local = await Direccion.create({ ...valores, personaId: dueno.personaId, tipo: TIPODIRECCION.LOC, nombre: 'Local' }, { transaction: t });
      await n.update({ direccionId: local.id }, { transaction: t });
    }
  }, { usuarioId });
  return miNegocio(usuarioId, req);
}

// Reemplaza el horario de la semana. Solo se versionan los días que cambian.
async function fijarHorarios(usuarioId, horarios, req) {
  const n = await exigirMio(usuarioId);
  await withTransaction(async (t) => {
    const actuales = await Horario.findAll({ where: { negocioId: n.id }, transaction: t });
    for (const h of horarios) {
      const valores = { cerrado: h.cerrado === true, apertura: h.cerrado ? null : h.apertura, cierre: h.cerrado ? null : h.cierre };
      const existente = actuales.find((x) => x.dia === h.dia);
      if (!existente) {
        await Horario.create({ negocioId: n.id, dia: h.dia, ...valores }, { transaction: t });
      } else if (existente.cerrado !== valores.cerrado || hhmm(existente.apertura) !== hhmm(valores.apertura) || hhmm(existente.cierre) !== hhmm(valores.cierre)) {
        await Horario.update(valores, { where: { negocioId: n.id, dia: h.dia }, transaction: t });
      }
    }
  }, { usuarioId });
  return miNegocio(usuarioId, req);
}

// Abrir/cerrar y aceptar pedidos: cambian a diario, por eso van a TNEGOCIOSESTADO (sin historial)
async function cambiarEstado(usuarioId, { abierto, aceptaPedidos }, req) {
  const n = await exigirMio(usuarioId);
  const cambios = { ultimoCambio: new Date() };
  if (abierto !== undefined) cambios.abierto = abierto === true;
  if (aceptaPedidos !== undefined) cambios.aceptaPedidos = aceptaPedidos === true;
  await NegocioEstado.update(cambios, { where: { negocioId: n.id } });
  auditar({ usuarioId, accion: 'NEGOCIOESTADO', entidad: 'NEGOCIOS', entidadId: n.id, detalle: cambios, req });
  return miNegocio(usuarioId, req);
}

async function subirImagen(usuarioId, tipo, base64, req) {
  const n = await exigirMio(usuarioId);
  await withTransaction(async (t) => {
    const archivo = await ArchivoService.guardarBase64({ base64, categoria: tipo === 'portada' ? 'PORTADA' : 'LOGO', propietario: usuarioId }, { transaction: t });
    await n.update(tipo === 'portada' ? { portadaId: archivo.id } : { logoId: archivo.id }, { transaction: t });
  }, { usuarioId });
  return miNegocio(usuarioId, req);
}

module.exports = {
  categorias, listar, obtener,
  delDueno, exigirMio, miNegocio, crearParaUsuario, crear, actualizar, fijarLocal, fijarHorarios, cambiarEstado, subirImagen,
  dentroDeHorario, aApi,
};
