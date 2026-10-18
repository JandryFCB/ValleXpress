const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const ArchivoService = require('../../shared/services/archivo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const withTransaction = require('../../shared/helpers/withTransaction');
const { auditar } = require('../../shared/services/log.service');
const { APROBACION } = require('../../shared/constants/codigos');

// SUSCRIPCIÓN MENSUAL (reemplaza a la comisión por pedido, 2026-10-18): cada vendedor y cada repartidor APROBADO paga
// una cuota fija al mes (calendario, hora de Ecuador). El mes en que lo aprueban es gratis: paga desde el siguiente,
// nunca antes de SUSCRIPCIONINICIO. Tiene hasta el día SUSCRIPCIONDIASGRACIA del mes para pagar; después el negocio
// deja de recibir pedidos y el repartidor no puede conectarse ni aceptar pedidos, hasta ponerse al día. Paga por
// transferencia y sube el comprobante: el administrador lo aprueba o lo rechaza con un motivo (un comprobante en
// revisión no bloquea). El administrador también puede registrar un pago a mano (efectivo).
// Los meses se CALCULAN (desde la aprobación hasta hoy); TSUSCRIPCIONPAGOS guarda solo los pagos.
const ZONA = 'America/Guayaquil';
const VIGENTE = "'2999-12-31 00:00:00-05'";
const HOY = `(now() AT TIME ZONE '${ZONA}')::date`;
const TIPOS = ['vendedor', 'repartidor'];
const NOMBREMES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

const consulta = (sql, replacements = {}, opciones = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT, ...opciones });
const num = (v) => Number(v || 0);
const fecha = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d).slice(0, 10));
const nombreMes = (mes) => `${NOMBREMES[Number(mes.slice(5, 7)) - 1]} ${mes.slice(0, 4)}`;
const sumarMeses = (mes, n) => {
  const d = new Date(`${mes}T12:00:00Z`);
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + n);
  return fecha(d);
};
const sumarDias = (dia, n) => {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return fecha(d);
};
const hoyEcuador = () => new Date(Date.now() - 5 * 3600 * 1000).toISOString().slice(0, 10);
const mesDe = (dia) => `${dia.slice(0, 7)}-01`;

// Quiénes pagan: repartidores aprobados y dueños de al menos un negocio aprobado, con la cuenta activa.
// "faprobado" = desde cuándo (si lo suspendieron y lo volvieron a aprobar, cuenta la última aprobación).
const SUSCRIPTORES = `
  SELECT r.cusuario, 'repartidor' AS tipo, COALESCE(r.faprobacion, r.fdesde) AS faprobado
    FROM trepartidores r
    JOIN tusuarios u ON u.cusuario = r.cusuario AND u.fhasta = ${VIGENTE} AND u.cestatususuario = '001'
   WHERE r.fhasta = ${VIGENTE} AND r.cestatusaprobacion = '${APROBACION.APROBADO}'
  UNION ALL
  SELECT n.cusuario, 'vendedor', MIN(COALESCE(n.faprobacion, n.fdesde))
    FROM tnegocios n
    JOIN tusuarios u ON u.cusuario = n.cusuario AND u.fhasta = ${VIGENTE} AND u.cestatususuario = '001'
   WHERE n.fhasta = ${VIGENTE} AND n.cestatusaprobacion = '${APROBACION.APROBADO}'
   GROUP BY n.cusuario`;

// ---------------------------------------------------------------------------------------------
// Configuración: cuotas, días para pagar, desde cuándo se cobra y la cuenta donde transferir
// ---------------------------------------------------------------------------------------------
const CAMPOSCUENTA = ['banco', 'tipo', 'numero', 'titular', 'identificacion', 'notas'];
const TIPOSCUENTA = ['ahorros', 'corriente'];

function cuentaDe(valor) {
  const v = valor && typeof valor === 'object' ? valor : { notas: valor ? String(valor) : '' };
  const c = Object.fromEntries(CAMPOSCUENTA.map((k) => [k, String(v[k] ?? '').trim()]));
  if (!TIPOSCUENTA.includes(c.tipo)) c.tipo = 'ahorros';
  return { ...c, completa: !!(c.banco && c.numero && c.titular) };
}

async function config() {
  const c = (clave, porDefecto) => ConfiguracionService.obtener(clave, porDefecto);
  const inicio = String(await c('SUSCRIPCIONINICIO', '2026-11-01')).slice(0, 10);
  return {
    cuotaVendedor: num(await c('SUSCRIPCIONVENDEDOR', 10)),
    cuotaRepartidor: num(await c('SUSCRIPCIONREPARTIDOR', 10)),
    diasGracia: Math.min(28, Math.max(1, Number(await c('SUSCRIPCIONDIASGRACIA', 5)) || 5)),
    inicio: mesDe(inicio),
    cuenta: cuentaDe(await c('LIQUIDACIONCUENTA', {})),
  };
}
const cuotaDe = (cfg, tipo) => (tipo === 'vendedor' ? cfg.cuotaVendedor : cfg.cuotaRepartidor);

const CLAVES = { cuotaVendedor: 'SUSCRIPCIONVENDEDOR', cuotaRepartidor: 'SUSCRIPCIONREPARTIDOR', diasGracia: 'SUSCRIPCIONDIASGRACIA', inicio: 'SUSCRIPCIONINICIO' };

async function fijarConfig(cambios, { transaction } = {}) {
  const actual = await config();
  const hechos = {};
  for (const [campo, clave] of Object.entries(CLAVES)) {
    if (cambios[campo] === undefined) continue;
    const valor = campo === 'inicio' ? mesDe(String(cambios[campo])) : Number(cambios[campo]);
    if (valor === actual[campo]) continue;
    await ConfiguracionService.fijar(clave, valor, { transaction });
    hechos[campo] = valor;
  }
  if (cambios.cuenta && typeof cambios.cuenta === 'object') {
    const { completa, ...previa } = actual.cuenta;
    const nueva = { ...previa };
    for (const k of CAMPOSCUENTA) if (cambios.cuenta[k] !== undefined) nueva[k] = String(cambios.cuenta[k]).trim();
    if (JSON.stringify(nueva) !== JSON.stringify(previa)) {
      await ConfiguracionService.fijar('LIQUIDACIONCUENTA', nueva, { transaction });
      hechos.cuenta = nueva;
    }
  }
  return hechos;
}

// ---------------------------------------------------------------------------------------------
// Estado de cuenta de un vendedor o repartidor
// ---------------------------------------------------------------------------------------------
async function suscriptor(usuarioId) {
  const filas = await consulta(`SELECT * FROM (${SUSCRIPTORES}) s WHERE s.cusuario = :u`, { u: usuarioId });
  return filas[0] ? { tipo: filas[0].tipo, aprobadoEn: filas[0].faprobado } : null;
}

// Primer mes que paga: el siguiente al de su aprobación, nunca antes del inicio del cobro
function primerMes(cfg, aprobadoEn) {
  const aprobado = mesDe(new Date(new Date(aprobadoEn).getTime() - 5 * 3600 * 1000).toISOString().slice(0, 10));
  const siguiente = sumarMeses(aprobado, 1);
  return siguiente > cfg.inicio ? siguiente : cfg.inicio;
}

async function pagosDe(usuarioId, req) {
  const filas = await consulta(`
    SELECT cpago AS id, mes, monto, referencia, carchivo, estado, motivorechazo, fcreacion, frevision
      FROM tsuscripcionpagos WHERE cusuario = :u ORDER BY mes DESC, fcreacion DESC`, { u: usuarioId });
  const urls = req ? await ArchivoService.mapaUrls(req, filas.map((f) => f.carchivo).filter(Boolean)) : {};
  return filas.map((f) => ({
    id: Number(f.id), mes: fecha(f.mes), monto: num(f.monto), referencia: f.referencia, estado: f.estado.toLowerCase(),
    motivoRechazo: f.motivorechazo, fecha: f.fcreacion, revisadoEn: f.frevision, imagen: f.carchivo ? urls[String(f.carchivo)]?.url || null : null,
  }));
}

// Meses desde el primero que paga hasta el actual, con su estado:
//   pagado, en_revision (comprobante enviado), por_pagar (aún a tiempo), vencido (pasó el día límite),
//   proximo (todavía no empieza: se puede adelantar)
// Si todo lo que va está pagado o en revisión, se ofrece adelantar el mes siguiente.
async function estado(usuarioId, req) {
  const cfg = await config();
  const s = await suscriptor(usuarioId);
  const pagos = await pagosDe(usuarioId, req);
  const base = { cuenta: cfg.cuenta, diasGracia: cfg.diasGracia, inicio: cfg.inicio };
  if (!s) {
    return { ...base, aplica: false, tipo: null, cuota: null, meses: [], saldoPendiente: 0, bloqueado: false, pagos: pagos.slice(0, 12) };
  }
  const cuota = cuotaDe(cfg, s.tipo);
  const hoy = hoyEcuador();
  const actual = mesDe(hoy);
  const desde = primerMes(cfg, s.aprobadoEn);
  const meses = [];
  for (let m = desde; m <= actual; m = sumarMeses(m, 1)) meses.push(m);
  const cubierto = (m) => pagos.some((p) => p.mes === m && (p.estado === 'aprobado' || p.estado === 'enviado'));
  if (!meses.length) meses.push(desde);                                      // aún no empieza a pagar
  else if (meses.every(cubierto)) meses.push(sumarMeses(actual, 1));         // al día: puede adelantar

  const lista = meses.map((m) => {
    const vence = sumarDias(m, cfg.diasGracia - 1);
    const delMes = pagos.filter((p) => p.mes === m);
    const aprobado = delMes.find((p) => p.estado === 'aprobado');
    const enviado = delMes.find((p) => p.estado === 'enviado');
    const estadoMes = aprobado ? 'pagado' : enviado ? 'en_revision' : m > actual ? 'proximo' : hoy > vence ? 'vencido' : 'por_pagar';
    const rechazado = !aprobado && !enviado ? delMes.find((p) => p.estado === 'rechazado') : null;
    return {
      mes: m,
      nombre: nombreMes(m),
      monto: aprobado ? aprobado.monto : enviado ? enviado.monto : cuota,
      vence,
      estado: estadoMes,
      ...(aprobado && { pago: aprobado }),
      ...(enviado && { comprobante: enviado }),
      ...(rechazado && { rechazado }),
    };
  }).reverse();

  const porPagar = lista.filter((m) => m.estado === 'por_pagar' || m.estado === 'vencido');
  return {
    ...base,
    aplica: true,
    tipo: s.tipo,
    cuota,
    meses: lista,
    saldoPendiente: Number(porPagar.reduce((t, m) => t + m.monto, 0).toFixed(2)),
    vencidos: lista.filter((m) => m.estado === 'vencido').length,
    enRevision: lista.filter((m) => m.estado === 'en_revision').length,
    bloqueado: lista.some((m) => m.estado === 'vencido'),
    pagos: pagos.slice(0, 12),
  };
}

// Usuarios (de la lista, o todos) con algún mes vencido sin pago aprobado ni comprobante en revisión
async function bloqueados(usuarios) {
  if (usuarios && !usuarios.length) return new Set();
  const cfg = await config();
  const filas = await consulta(`
    WITH s AS (
      SELECT x.cusuario,
             GREATEST(CAST(:inicio AS date),
                      (date_trunc('month', x.faprobado AT TIME ZONE '${ZONA}') + interval '1 month')::date) AS desde
        FROM (${SUSCRIPTORES}) x
       ${usuarios ? 'WHERE x.cusuario IN (:usuarios)' : ''})
    SELECT DISTINCT s.cusuario
      FROM s, generate_series(s.desde, date_trunc('month', ${HOY})::date, interval '1 month') AS m
     WHERE m::date + CAST(:dias AS int) <= ${HOY}
       AND NOT EXISTS (SELECT 1 FROM tsuscripcionpagos p
                        WHERE p.cusuario = s.cusuario AND p.mes = m::date AND p.estado IN ('ENVIADO', 'APROBADO'))`,
  { inicio: cfg.inicio, dias: cfg.diasGracia, ...(usuarios && { usuarios }) });
  return new Set(filas.map((f) => f.cusuario));
}

// Negocios (de la lista) cuyo dueño tiene la suscripción vencida: no reciben pedidos
async function negociosBloqueados(ids) {
  if (!ids?.length) return new Set();
  const negocios = await consulta(`SELECT cnegocio AS id, cusuario FROM tnegocios WHERE fhasta = ${VIGENTE} AND cnegocio IN (:ids)`, { ids });
  const conDeuda = await bloqueados([...new Set(negocios.map((n) => n.cusuario))]);
  return new Set(negocios.filter((n) => conDeuda.has(n.cusuario)).map((n) => String(n.id)));
}

// El repartidor con la suscripción vencida no se conecta ni acepta pedidos
async function exigirAlDia(usuarioId) {
  if (!(await bloqueados([usuarioId])).has(usuarioId)) return;
  throw AppError.forbidden('Tu suscripción está vencida. Págala y sube tu comprobante en "Mi suscripción" para seguir trabajando', 'SUSCRIPCIONVENCIDA');
}

// ---------------------------------------------------------------------------------------------
// Vendedor o repartidor: subir el comprobante de un mes
// ---------------------------------------------------------------------------------------------
function exigirPagable(m) {
  if (!m) throw AppError.badRequest('Ese mes no está en tu suscripción', 'MESINVALIDO');
  if (m.estado === 'pagado') throw AppError.conflict('Ese mes ya está pagado', 'YAPAGADO');
  if (m.estado === 'en_revision') throw AppError.conflict('Ya enviaste el comprobante de ese mes: lo estamos revisando', 'COMPROBANTEENREVISION');
}

const duplicado = (e) => e.name === 'SequelizeUniqueConstraintError' || /uqsuspagmes/i.test(e.message || '');

async function subirComprobante(usuario, { mes, imagen, referencia }, req) {
  const cuenta = await estado(usuario.id);
  if (!cuenta.aplica) throw AppError.forbidden('Tu cuenta todavía no paga suscripción (se cobra desde que te aprueban)', 'SINSUSCRIPCION');
  const m = cuenta.meses.find((x) => x.mes === mesDe(String(mes)));
  exigirPagable(m);
  try {
    await withTransaction(async (t) => {
      const archivo = await ArchivoService.guardarBase64({ base64: imagen, categoria: 'DOCUMENTO', propietario: usuario.id, nombreOriginal: `suscripcion-${m.mes}` }, { transaction: t });
      await sequelize.query(
        `INSERT INTO tsuscripcionpagos (cusuario, mes, monto, referencia, carchivo, cusuario_registro)
         VALUES (:u, :mes, :monto, :referencia, :archivo, :u)`,
        { replacements: { u: usuario.id, mes: m.mes, monto: m.monto, referencia: referencia?.trim() || null, archivo: archivo.id }, transaction: t },
      );
    }, { usuarioId: usuario.id });
  } catch (e) {
    if (duplicado(e)) throw AppError.conflict('Ya enviaste el comprobante de ese mes: lo estamos revisando', 'COMPROBANTEENREVISION');
    throw e;
  }
  auditar({ usuarioId: usuario.id, accion: 'SUSCRIPCIONCOMPROBANTE', entidad: 'SUSCRIPCIONES', entidadId: usuario.id, detalle: { mes: m.mes, monto: m.monto }, req });
  await NotificacionService.notificarAdministradores({
    io: req.io, tipo: 'comprobante_nuevo', titulo: 'Comprobante por revisar 🧾',
    mensaje: `${usuario.nombre || usuario.id} (${cuenta.tipo}) subió su comprobante de $${m.monto.toFixed(2)} de ${m.nombre}`,
  });
  return estado(usuario.id, req);
}

// ---------------------------------------------------------------------------------------------
// Administrador
// ---------------------------------------------------------------------------------------------
// Todos los que pagan, con cómo van, y los comprobantes que esperan revisión
async function resumen(req) {
  const cfg = await config();
  const filas = await consulta(`
    SELECT s.cusuario AS usuario, s.tipo, s.faprobado, p.nombres, p.apellidos
      FROM (${SUSCRIPTORES}) s
      JOIN tusuarios u ON u.cusuario = s.cusuario AND u.fhasta = ${VIGENTE}
      JOIN tpersonas p ON p.cpersona = u.cpersona AND p.fhasta = ${VIGENTE}
     ORDER BY p.nombres, p.apellidos`);
  const suscriptores = [];
  for (const f of filas) {
    const e = await estado(f.usuario);
    const actual = e.meses.find((m) => m.mes === mesDe(hoyEcuador()));
    suscriptores.push({
      usuario: f.usuario, nombre: `${f.nombres} ${f.apellidos}`.trim(), tipo: f.tipo, cuota: e.cuota,
      saldoPendiente: e.saldoPendiente, vencidos: e.vencidos, enRevision: e.enRevision, bloqueado: e.bloqueado,
      estadoMesActual: actual?.estado || 'proximo',
      alDia: !e.bloqueado && e.saldoPendiente === 0,
    });
  }
  const orden = (s) => (s.enRevision ? 0 : s.bloqueado ? 1 : s.saldoPendiente > 0 ? 2 : 3);
  suscriptores.sort((a, b) => orden(a) - orden(b) || a.nombre.localeCompare(b.nombre));
  return { config: cfg, comprobantes: await porRevisar(req), suscriptores };
}

async function porRevisar(req) {
  const filas = await consulta(`
    SELECT c.cpago AS id, c.cusuario AS usuario, c.mes, c.monto, c.referencia, c.carchivo, c.fcreacion, u.crol, p.nombres, p.apellidos
      FROM tsuscripcionpagos c
      JOIN tusuarios u ON u.cusuario = c.cusuario AND u.fhasta = ${VIGENTE}
      JOIN tpersonas p ON p.cpersona = u.cpersona AND p.fhasta = ${VIGENTE}
     WHERE c.estado = 'ENVIADO'
     ORDER BY c.fcreacion`);
  const urls = req ? await ArchivoService.mapaUrls(req, filas.map((f) => f.carchivo)) : {};
  return filas.map((f) => ({
    id: Number(f.id), usuario: f.usuario, nombre: `${f.nombres} ${f.apellidos}`.trim(), tipo: f.crol === '002' ? 'vendedor' : 'repartidor',
    mes: fecha(f.mes), nombreMes: nombreMes(fecha(f.mes)), monto: num(f.monto), referencia: f.referencia, fecha: f.fcreacion,
    imagen: urls[String(f.carchivo)]?.url || null,
  }));
}

const contarPorRevisar = async () => Number((await consulta("SELECT COUNT(*) AS n FROM tsuscripcionpagos WHERE estado = 'ENVIADO'"))[0].n);

async function avisar(req, usuarioId, tipo, titulo, mensaje) {
  await NotificacionService.notificar({ io: req.io, usuarioId, tipo, titulo, mensaje });
}

async function pagoEnviado(id) {
  const [c] = await consulta('SELECT cpago AS id, cusuario, mes, monto, estado FROM tsuscripcionpagos WHERE cpago = :id', { id });
  if (!c) throw AppError.notFound('Comprobante no encontrado', 'COMPROBANTENOENCONTRADO');
  if (c.estado !== 'ENVIADO') throw AppError.conflict('Ese comprobante ya fue revisado', 'COMPROBANTEREVISADO');
  return { ...c, mes: fecha(c.mes), monto: num(c.monto) };
}

async function aprobar(admin, id, req) {
  const c = await pagoEnviado(id);
  await sequelize.query(
    "UPDATE tsuscripcionpagos SET estado = 'APROBADO', frevision = now(), cusuario_revision = :admin WHERE cpago = :id AND estado = 'ENVIADO'",
    { replacements: { id: c.id, admin: admin.id } },
  );
  auditar({ usuarioId: admin.id, accion: 'SUSCRIPCIONAPROBADA', entidad: 'SUSCRIPCIONES', entidadId: c.cusuario, detalle: { pago: Number(c.id), mes: c.mes, monto: c.monto }, req });
  await avisar(req, c.cusuario, 'suscripcion_pagada', 'Recibimos tu pago ✅', `Aprobamos tu pago de $${c.monto.toFixed(2)} de ${nombreMes(c.mes)}. ¡Gracias!`);
  return estado(c.cusuario, req);
}

async function rechazar(admin, id, { motivo }, req) {
  const c = await pagoEnviado(id);
  await sequelize.query(
    "UPDATE tsuscripcionpagos SET estado = 'RECHAZADO', motivorechazo = :motivo, frevision = now(), cusuario_revision = :admin WHERE cpago = :id AND estado = 'ENVIADO'",
    { replacements: { id: c.id, motivo: motivo.trim(), admin: admin.id } },
  );
  auditar({ usuarioId: admin.id, accion: 'SUSCRIPCIONRECHAZADA', entidad: 'SUSCRIPCIONES', entidadId: c.cusuario, detalle: { pago: Number(c.id), mes: c.mes, motivo }, req });
  await avisar(req, c.cusuario, 'comprobante_rechazado', 'Revisa tu comprobante',
    `No pudimos validar tu comprobante de ${nombreMes(c.mes)}: ${motivo.trim()}. Sube uno nuevo desde "Mi suscripción"`);
  return estado(c.cusuario, req);
}

// Pago registrado a mano (efectivo o transferencia sin comprobante). Si había uno en revisión, queda aprobado.
async function registrarPago(admin, usuarioId, { mes, referencia }, req) {
  const cuenta = await estado(usuarioId);
  if (!cuenta.aplica) throw AppError.notFound('Ese usuario no paga suscripción (no es un vendedor o repartidor aprobado)', 'SINSUSCRIPCION');
  const m = cuenta.meses.find((x) => x.mes === mesDe(String(mes)));
  if (!m) throw AppError.badRequest('Ese mes no está en su suscripción', 'MESINVALIDO');
  if (m.estado === 'pagado') throw AppError.conflict('Ese mes ya está pagado', 'YAPAGADO');
  try {
    await withTransaction(async (t) => {
      const [, r] = await sequelize.query(
        `UPDATE tsuscripcionpagos SET estado = 'APROBADO', frevision = now(), cusuario_revision = :admin,
                referencia = COALESCE(NULLIF(:referencia, ''), referencia)
          WHERE cusuario = :u AND mes = :mes AND estado = 'ENVIADO'`,
        { replacements: { u: usuarioId, mes: m.mes, admin: admin.id, referencia: referencia?.trim() || '' }, transaction: t },
      );
      if (!r?.rowCount) {
        await sequelize.query(
          `INSERT INTO tsuscripcionpagos (cusuario, mes, monto, referencia, estado, cusuario_registro, frevision, cusuario_revision)
           VALUES (:u, :mes, :monto, :referencia, 'APROBADO', :admin, now(), :admin)`,
          { replacements: { u: usuarioId, mes: m.mes, monto: m.monto, referencia: referencia?.trim() || null, admin: admin.id }, transaction: t },
        );
      }
    }, { usuarioId: admin.id });
  } catch (e) {
    if (duplicado(e)) throw AppError.conflict('Ese mes ya está pagado', 'YAPAGADO');
    throw e;
  }
  auditar({ usuarioId: admin.id, accion: 'SUSCRIPCIONPAGOMANUAL', entidad: 'SUSCRIPCIONES', entidadId: usuarioId, detalle: { mes: m.mes, monto: m.monto, referencia: referencia || null }, req });
  await avisar(req, usuarioId, 'suscripcion_pagada', 'Recibimos tu pago ✅', `Registramos tu pago de $${m.monto.toFixed(2)} de ${m.nombre}. ¡Gracias!`);
  return estado(usuarioId, req);
}

// Lo cobrado (pagos aprobados) entre dos fechas, para el resumen del administrador
async function cobrado({ desde, hasta } = {}) {
  const filas = await consulta(`
    SELECT c.cpago AS id, c.cusuario AS usuario, c.mes, c.monto, c.referencia, c.frevision AS fecha, u.crol, p.nombres, p.apellidos
      FROM tsuscripcionpagos c
      JOIN tusuarios u ON u.cusuario = c.cusuario AND u.fhasta = ${VIGENTE}
      JOIN tpersonas p ON p.cpersona = u.cpersona AND p.fhasta = ${VIGENTE}
     WHERE c.estado = 'APROBADO'
       ${desde ? `AND (c.frevision AT TIME ZONE '${ZONA}')::date >= CAST(:desde AS date)` : ''}
       ${hasta ? `AND (c.frevision AT TIME ZONE '${ZONA}')::date <= CAST(:hasta AS date)` : ''}
     ORDER BY c.frevision DESC`, { ...(desde && { desde }), ...(hasta && { hasta }) });
  return filas.map((f) => ({
    id: Number(f.id), usuario: f.usuario, nombre: `${f.nombres} ${f.apellidos}`.trim(), tipo: f.crol === '002' ? 'vendedor' : 'repartidor',
    mes: fecha(f.mes), nombreMes: nombreMes(fecha(f.mes)), monto: num(f.monto), referencia: f.referencia, fecha: f.fecha,
  }));
}

// ---------------------------------------------------------------------------------------------
// Recordatorios (push + aviso en la app), una sola vez cada uno por mes:
//   inicio     desde el día 1: "Tu cuota de noviembre es $10. Tienes hasta el día 5"
//   manana     el día antes del límite: "Mañana vence tu suscripción"
//   bloqueado  pasado el límite: "Tu suscripción venció: no recibes pedidos / no puedes conectarte"
// No se avisa de un mes que ya está pagado o con el comprobante en revisión. Solo de 8:00 a 21:00 (hora de Ecuador).
// ---------------------------------------------------------------------------------------------
const TIPORECORDATORIO = 'suscripcion_recordatorio';

async function recordar({ io, ahora = new Date() } = {}) {
  const hora = new Date(ahora.getTime() - 5 * 3600 * 1000);
  if (hora.getUTCHours() < 8 || hora.getUTCHours() >= 21) return 0;
  const hoy = hora.toISOString().slice(0, 10);
  const mes = mesDe(hoy);
  const cfg = await config();
  const vence = sumarDias(mes, cfg.diasGracia - 1);
  const manana = sumarDias(vence, -1);
  const etapa = hoy > vence ? 'bloqueado' : hoy === manana ? 'manana' : 'inicio';

  // Suscriptores que pagan este mes (su primer mes ya empezó) y no lo tienen pagado ni en revisión
  const filas = await consulta(`
    SELECT s.cusuario, s.tipo
      FROM (${SUSCRIPTORES}) s
     WHERE GREATEST(CAST(:inicio AS date), (date_trunc('month', s.faprobado AT TIME ZONE '${ZONA}') + interval '1 month')::date) <= CAST(:mes AS date)
       AND NOT EXISTS (SELECT 1 FROM tsuscripcionpagos p WHERE p.cusuario = s.cusuario AND p.mes = CAST(:mes AS date) AND p.estado IN ('ENVIADO', 'APROBADO'))
       AND NOT EXISTS (SELECT 1 FROM tnotificaciones n WHERE n.cusuario = s.cusuario AND n.tipo = :tipo AND n.datos->>'clave' = :clave)`,
  { inicio: cfg.inicio, mes, tipo: TIPORECORDATORIO, clave: `${mes}:${etapa}` });

  const nombre = nombreMes(mes).split(' ')[0];
  for (const f of filas) {
    const cuota = cuotaDe(cfg, f.tipo);
    const bloqueo = f.tipo === 'vendedor' ? 'tus negocios no reciben pedidos' : 'no puedes conectarte ni aceptar pedidos';
    const [titulo, mensaje] = {
      inicio: [`Tu cuota de ${nombre}: $${cuota.toFixed(2)}`, `Tienes hasta el ${Number(vence.slice(8))} de ${nombre} para pagarla. Transfiere y sube el comprobante en "Mi suscripción"`],
      manana: ['Mañana vence tu suscripción ⏰', `Paga tu cuota de $${cuota.toFixed(2)} y sube el comprobante hoy o mañana; si no, ${bloqueo}`],
      bloqueado: ['Tu suscripción venció', `Hasta que pagues tu cuota de ${nombre}, ${bloqueo}. Sube el comprobante en "Mi suscripción"`],
    }[etapa];
    await NotificacionService.notificar({ io, usuarioId: f.cusuario, tipo: TIPORECORDATORIO, titulo, mensaje, datos: { clave: `${mes}:${etapa}`, mes } });
  }
  return filas.length;
}

// Revisa cada 15 minutos (y una vez al arrancar). No impide que el proceso termine.
function iniciarRecordatorios(io) {
  const pasada = () => recordar({ io }).catch((e) => require('../../shared/services/log.service').logMensaje({
    nivel: 'ADVERTENCIA', modulo: 'SUSCRIPCIONES', accion: 'RECORDATORIOFALLIDO', mensaje: 'No se pudieron enviar los recordatorios', detalle: { error: e.message },
  }));
  setTimeout(pasada, 10 * 1000).unref();
  return setInterval(pasada, 15 * 60 * 1000).unref();
}

module.exports = {
  recordar, iniciarRecordatorios,
  TIPOS, TIPOSCUENTA, config, fijarConfig, estado, bloqueados, negociosBloqueados, exigirAlDia,
  subirComprobante, resumen, porRevisar, contarPorRevisar, aprobar, rechazar, registrarPago, cobrado, nombreMes,
};
