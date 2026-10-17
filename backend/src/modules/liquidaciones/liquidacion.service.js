const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const ArchivoService = require('../../shared/services/archivo.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const withTransaction = require('../../shared/helpers/withTransaction');
const { auditar } = require('../../shared/services/log.service');
const { ESTADOPEDIDO: E } = require('../../shared/constants/codigos');

// LIQUIDACIONES (opción A): cada semana (lunes a domingo, hora de Ecuador) el negocio le debe a ValleXpress la
// comisión de sus pedidos entregados. Las semanas se CALCULAN de los pedidos (siempre cuadran); TLIQUIDACIONES
// guarda solo los pagos. El negocio sube el COMPROBANTE de su transferencia y el administrador lo aprueba (la
// semana queda pagada) o lo rechaza con un motivo. Una semana cerrada sin pagar, pasados los días de gracia,
// deja al negocio sin recibir pedidos; si su comprobante está en revisión, no lo bloquea.
const ZONA = 'America/Guayaquil';
const VIGENTE = "'2999-12-31 00:00:00-05'";
const VENDIDOS = [E.ENTREGADO, E.RECIBIDO];
const SEMANA = `date_trunc('week', p.fpedido AT TIME ZONE '${ZONA}')::date`;
const HOY = `(now() AT TIME ZONE '${ZONA}')::date`;
const ESTASEMANA = `date_trunc('week', now() AT TIME ZONE '${ZONA}')::date`;
// La semana tiene un comprobante esperando revisión
const ENREVISION = (negocio, semana) => `EXISTS (SELECT 1 FROM tliquidacioncomprobantes c WHERE c.cnegocio = ${negocio} AND c.semana = ${semana} AND c.estado = 'ENVIADO')`;

const consulta = (sql, replacements = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT });
const num = (v) => Number(v || 0);
const fecha = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d).slice(0, 10));

// ---------------------------------------------------------------------------------------------
// Configuración: días de gracia y la cuenta donde transfieren los negocios
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
  return {
    diasGracia: Math.max(0, Number(await ConfiguracionService.obtener('LIQUIDACIONDIASGRACIA', 7)) || 0),
    cuenta: cuentaDe(await ConfiguracionService.obtener('LIQUIDACIONCUENTA', {})),
  };
}

async function fijarConfig(cambios, { transaction } = {}) {
  const actual = await config();
  const hechos = {};
  if (cambios.diasGracia !== undefined && Number(cambios.diasGracia) !== actual.diasGracia) {
    await ConfiguracionService.fijar('LIQUIDACIONDIASGRACIA', Number(cambios.diasGracia), { transaction });
    hechos.diasGracia = Number(cambios.diasGracia);
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
// Semanas y estado de cuenta
// ---------------------------------------------------------------------------------------------
// Último comprobante de cada semana del negocio (para mostrar "en revisión" o el motivo del rechazo)
async function comprobantesDe(negocioId, req) {
  const filas = await consulta(`
    SELECT DISTINCT ON (semana) ccomprobante AS id, semana, carchivo, monto, referencia, estado, motivorechazo, fcreacion
      FROM tliquidacioncomprobantes WHERE cnegocio = :n ORDER BY semana, fcreacion DESC`, { n: negocioId });
  const urls = req ? await ArchivoService.mapaUrls(req, filas.map((f) => f.carchivo)) : {};
  return Object.fromEntries(filas.map((f) => [fecha(f.semana), {
    id: Number(f.id), estado: f.estado.toLowerCase(), monto: num(f.monto), referencia: f.referencia, motivoRechazo: f.motivorechazo,
    fecha: f.fcreacion, imagen: urls[String(f.carchivo)]?.url || null,
  }]));
}

// Semanas de un negocio (las últimas 12 con ventas), con su estado:
//   en_curso (la semana actual), pendiente / vencida (cerrada sin pagar), en_revision (comprobante enviado),
//   pagada, sin_cargo (comisión 0)
async function semanas(negocioId, req) {
  const { diasGracia } = await config();
  const filas = await consulta(`
    WITH s AS (
      SELECT ${SEMANA} AS semana, COUNT(*) AS pedidos, SUM(p.subtotal) AS ventas, SUM(p.comision) AS comision
        FROM tpedidos p
       WHERE p.fhasta = ${VIGENTE} AND p.cnegocio = :n AND p.cestatuspedido IN (:vendidos)
       GROUP BY 1)
    SELECT s.*, l.comision AS pagado, l.fpago, l.referencia,
           s.semana = ${ESTASEMANA} AS actual,
           s.semana + (7 + :dias) <= ${HOY} AS vencida
      FROM s LEFT JOIN tliquidaciones l ON l.cnegocio = :n AND l.semana = s.semana
     ORDER BY s.semana DESC LIMIT 12`, { n: negocioId, vendidos: VENDIDOS, dias: diasGracia });
  const comprobantes = await comprobantesDe(negocioId, req);

  return filas.map((f) => {
    const desde = fecha(f.semana);
    const comprobante = comprobantes[desde] || null;
    const comision = num(f.pagado ?? f.comision);
    let estado = f.pagado != null ? 'pagada' : f.actual ? 'en_curso' : comision === 0 ? 'sin_cargo' : f.vencida ? 'vencida' : 'pendiente';
    if ((estado === 'pendiente' || estado === 'vencida') && comprobante?.estado === 'enviado') estado = 'en_revision';
    const dia = (n) => {
      const d = new Date(`${desde}T12:00:00Z`);
      d.setUTCDate(d.getUTCDate() + n);
      return fecha(d);
    };
    return {
      semana: desde,
      hasta: dia(6),
      pedidos: Number(f.pedidos),
      ventas: num(f.ventas),
      comision,
      recibeNegocio: Number((num(f.ventas) - comision).toFixed(2)),
      estado,
      ...(['pendiente', 'vencida', 'en_revision'].includes(estado) && { vence: dia(7 + diasGracia) }),
      ...(f.pagado != null && { fechaPago: f.fpago, referencia: f.referencia }),
      ...(comprobante && estado !== 'pagada' && estado !== 'en_curso' && { comprobante }),
    };
  });
}

// Estado de cuenta del negocio: sus semanas, cuánto debe, si ya está bloqueado y a dónde transferir
async function estadoDeCuenta(negocioId, req) {
  const lista = await semanas(negocioId, req);
  const { diasGracia, cuenta } = await config();
  const porPagar = lista.filter((s) => ['pendiente', 'vencida', 'en_revision'].includes(s.estado));
  return {
    semanas: lista,
    saldoPendiente: Number(porPagar.reduce((t, s) => t + s.comision, 0).toFixed(2)),
    bloqueado: lista.some((s) => s.estado === 'vencida'),
    diasGracia,
    cuenta,
  };
}

// Negocios con alguna semana vencida sin pagar y sin comprobante en revisión (no reciben pedidos)
async function conDeudaVencida(ids) {
  const { diasGracia } = await config();
  if (ids && !ids.length) return new Set();
  const filas = await consulta(`
    SELECT DISTINCT p.cnegocio AS id
      FROM tpedidos p
     WHERE p.fhasta = ${VIGENTE} AND p.cestatuspedido IN (:vendidos) AND p.comision > 0
       AND ${SEMANA} + (7 + :dias) <= ${HOY}
       ${ids ? 'AND p.cnegocio IN (:ids)' : ''}
       AND NOT EXISTS (SELECT 1 FROM tliquidaciones l WHERE l.cnegocio = p.cnegocio AND l.semana = ${SEMANA})
       AND NOT ${ENREVISION('p.cnegocio', SEMANA)}`,
  { vendidos: VENDIDOS, dias: diasGracia, ...(ids && { ids }) });
  return new Set(filas.map((f) => String(f.id)));
}

// ---------------------------------------------------------------------------------------------
// Administrador
// ---------------------------------------------------------------------------------------------
// Negocios que deben semanas cerradas: saldo, si ya están bloqueados y cuántos comprobantes esperan revisión
async function pendientes() {
  const { diasGracia } = await config();
  const filas = await consulta(`
    WITH s AS (
      SELECT p.cnegocio, ${SEMANA} AS semana, SUM(p.comision) AS comision
        FROM tpedidos p
       WHERE p.fhasta = ${VIGENTE} AND p.cestatuspedido IN (:vendidos)
       GROUP BY 1, 2
      HAVING SUM(p.comision) > 0)
    SELECT n.cnegocio AS id, n.nombre, COUNT(*) AS semanas, SUM(s.comision) AS saldo,
           BOOL_OR(s.semana + (7 + :dias) <= ${HOY} AND NOT ${ENREVISION('s.cnegocio', 's.semana')}) AS bloqueado,
           COUNT(*) FILTER (WHERE ${ENREVISION('s.cnegocio', 's.semana')}) AS porrevisar
      FROM s
      JOIN tnegocios n ON n.cnegocio = s.cnegocio AND n.fhasta = ${VIGENTE}
     WHERE s.semana < ${ESTASEMANA}
       AND NOT EXISTS (SELECT 1 FROM tliquidaciones l WHERE l.cnegocio = s.cnegocio AND l.semana = s.semana)
     GROUP BY n.cnegocio, n.nombre
     ORDER BY porrevisar DESC, bloqueado DESC, saldo DESC`, { vendidos: VENDIDOS, dias: diasGracia });
  return filas.map((f) => ({
    negocioId: Number(f.id), nombre: f.nombre, semanas: Number(f.semanas), saldo: num(f.saldo), bloqueado: f.bloqueado, porRevisar: Number(f.porrevisar),
  }));
}

async function duenoDe(negocioId) {
  const [d] = await consulta(`SELECT cusuario, nombre FROM tnegocios WHERE cnegocio = :n AND fhasta = ${VIGENTE}`, { n: negocioId });
  return d;
}

// Registra el pago de una semana cerrada (foto de lo cobrado) dentro de la transacción "t"
async function insertarPago(admin, negocioId, s, referencia, t) {
  try {
    await sequelize.query(
      `INSERT INTO tliquidaciones (cnegocio, semana, pedidos, ventas, comision, referencia, cusuario)
       VALUES (:n, :semana, :pedidos, :ventas, :comision, :referencia, :admin)`,
      { replacements: { n: negocioId, semana: s.semana, pedidos: s.pedidos, ventas: s.ventas, comision: s.comision, referencia: referencia?.trim() || null, admin: admin.id }, transaction: t },
    );
  } catch (e) {
    if (e.name === 'SequelizeUniqueConstraintError' || /iukliquidaciones/i.test(e.message)) throw AppError.conflict('Esa semana ya está pagada', 'YAPAGADA');
    throw e;
  }
}

function exigirCobrable(s) {
  if (!s) throw AppError.notFound('Ese negocio no tiene ventas en esa semana', 'SEMANANOENCONTRADA');
  if (s.estado === 'pagada') throw AppError.conflict('Esa semana ya está pagada', 'YAPAGADA');
  if (s.estado === 'en_curso') throw AppError.conflict('La semana todavía no termina: se liquida desde el lunes', 'SEMANAENCURSO');
  if (s.estado === 'sin_cargo') throw AppError.conflict('Esa semana no tiene comisión que cobrar', 'SINCOMISION');
}

async function avisarPago(req, negocioId, s) {
  const dueno = await duenoDe(negocioId);
  await NotificacionService.notificar({
    io: req.io, usuarioId: dueno?.cusuario, tipo: 'liquidacion_pagada', titulo: 'Recibimos tu pago ✅',
    mensaje: `Registramos tu pago de $${s.comision.toFixed(2)} de la comisión de la semana del ${s.semana}. ¡Gracias!`,
  });
}

// Pago registrado a mano (efectivo o transferencia sin comprobante). Si había uno en revisión, queda aprobado.
async function registrarPago(admin, negocioId, { semana, referencia }, req) {
  const s = (await semanas(negocioId)).find((x) => x.semana === semana);
  exigirCobrable(s);
  await withTransaction(async (t) => {
    await insertarPago(admin, negocioId, s, referencia, t);
    await sequelize.query(
      `UPDATE tliquidacioncomprobantes SET estado = 'APROBADO', frevision = now(), cusuario_revision = :admin
        WHERE cnegocio = :n AND semana = :semana AND estado = 'ENVIADO'`,
      { replacements: { n: negocioId, semana, admin: admin.id }, transaction: t },
    );
  });
  auditar({ usuarioId: admin.id, accion: 'LIQUIDACIONPAGADA', entidad: 'NEGOCIOS', entidadId: negocioId, detalle: { semana, comision: s.comision, referencia: referencia || null }, req });
  await avisarPago(req, negocioId, s);
  return estadoDeCuenta(negocioId, req);
}

async function comprobante(id) {
  const [c] = await consulta('SELECT ccomprobante AS id, cnegocio, semana, referencia, estado FROM tliquidacioncomprobantes WHERE ccomprobante = :id', { id });
  if (!c) throw AppError.notFound('Comprobante no encontrado', 'COMPROBANTENOENCONTRADO');
  if (c.estado !== 'ENVIADO') throw AppError.conflict('Ese comprobante ya fue revisado', 'COMPROBANTEREVISADO');
  return { ...c, negocioId: Number(c.cnegocio), semana: fecha(c.semana) };
}

// Aprobar un comprobante: la semana queda pagada con la referencia del negocio
async function aprobarComprobante(admin, id, req) {
  const c = await comprobante(id);
  const s = (await semanas(c.negocioId)).find((x) => x.semana === c.semana);
  exigirCobrable(s);
  await withTransaction(async (t) => {
    await insertarPago(admin, c.negocioId, s, c.referencia || `Comprobante #${c.id}`, t);
    await sequelize.query("UPDATE tliquidacioncomprobantes SET estado = 'APROBADO', frevision = now(), cusuario_revision = :admin WHERE ccomprobante = :id",
      { replacements: { id: c.id, admin: admin.id }, transaction: t });
  });
  auditar({ usuarioId: admin.id, accion: 'COMPROBANTEAPROBADO', entidad: 'NEGOCIOS', entidadId: c.negocioId, detalle: { comprobante: c.id, semana: c.semana, comision: s.comision }, req });
  await avisarPago(req, c.negocioId, s);
  return estadoDeCuenta(c.negocioId, req);
}

// Rechazar un comprobante (no se lee, el monto no cuadra...): el negocio ve el motivo y puede subir otro
async function rechazarComprobante(admin, id, { motivo }, req) {
  const c = await comprobante(id);
  await sequelize.query(
    "UPDATE tliquidacioncomprobantes SET estado = 'RECHAZADO', motivorechazo = :motivo, frevision = now(), cusuario_revision = :admin WHERE ccomprobante = :id",
    { replacements: { id: c.id, motivo: motivo.trim(), admin: admin.id } },
  );
  auditar({ usuarioId: admin.id, accion: 'COMPROBANTERECHAZADO', entidad: 'NEGOCIOS', entidadId: c.negocioId, detalle: { comprobante: c.id, semana: c.semana, motivo }, req });
  const dueno = await duenoDe(c.negocioId);
  await NotificacionService.notificar({
    io: req.io, usuarioId: dueno?.cusuario, tipo: 'comprobante_rechazado', titulo: 'Revisa tu comprobante',
    mensaje: `No pudimos validar tu comprobante de la semana del ${c.semana}: ${motivo.trim()}. Sube uno nuevo desde "Mis cuentas"`,
  });
  return estadoDeCuenta(c.negocioId, req);
}

// ---------------------------------------------------------------------------------------------
// Negocio: subir el comprobante de una semana por pagar
// ---------------------------------------------------------------------------------------------
async function subirComprobante(usuario, negocioId, { semana, imagen, referencia }, req) {
  const s = (await semanas(negocioId)).find((x) => x.semana === semana);
  exigirCobrable(s);
  if (s.estado === 'en_revision') throw AppError.conflict('Ya enviaste un comprobante de esa semana: lo estamos revisando', 'COMPROBANTEENREVISION');
  await withTransaction(async (t) => {
    const archivo = await ArchivoService.guardarBase64({ base64: imagen, categoria: 'DOCUMENTO', propietario: usuario.id, nombreOriginal: `comprobante-${semana}` }, { transaction: t });
    await sequelize.query(
      `INSERT INTO tliquidacioncomprobantes (cnegocio, semana, carchivo, monto, referencia, cusuario)
       VALUES (:n, :semana, :archivo, :monto, :referencia, :usuario)`,
      { replacements: { n: negocioId, semana, archivo: archivo.id, monto: s.comision, referencia: referencia?.trim() || null, usuario: usuario.id }, transaction: t },
    );
  }, { usuarioId: usuario.id });
  auditar({ usuarioId: usuario.id, accion: 'COMPROBANTESUBIDO', entidad: 'NEGOCIOS', entidadId: negocioId, detalle: { semana, monto: s.comision }, req });
  const dueno = await duenoDe(negocioId);
  await NotificacionService.notificarAdministradores({
    io: req.io, tipo: 'comprobante_nuevo', titulo: 'Comprobante por revisar 🧾',
    mensaje: `${dueno?.nombre || 'Un negocio'} subió su comprobante de $${s.comision.toFixed(2)} (semana del ${semana})`,
  });
  return estadoDeCuenta(negocioId, req);
}

module.exports = {
  config, fijarConfig, semanas, estadoDeCuenta, conDeudaVencida, pendientes,
  registrarPago, aprobarComprobante, rechazarComprobante, subirComprobante, TIPOSCUENTA,
};
