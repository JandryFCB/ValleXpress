const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const { auditar } = require('../../shared/services/log.service');
const { ESTADOPEDIDO: E } = require('../../shared/constants/codigos');

// LIQUIDACIONES (opción A): cada semana (lunes a domingo, hora de Ecuador) el negocio le debe a ValleXpress la
// comisión de sus pedidos entregados. Las semanas se CALCULAN de los pedidos (siempre cuadran); TLIQUIDACIONES
// guarda solo los pagos. Una semana cerrada sin pagar, pasados los días de gracia, deja al negocio sin recibir
// pedidos hasta ponerse al día.
const ZONA = 'America/Guayaquil';
const VIGENTE = "'2999-12-31 00:00:00-05'";
const VENDIDOS = [E.ENTREGADO, E.RECIBIDO];
const SEMANA = `date_trunc('week', p.fpedido AT TIME ZONE '${ZONA}')::date`;
const HOY = `(now() AT TIME ZONE '${ZONA}')::date`;
const ESTASEMANA = `date_trunc('week', now() AT TIME ZONE '${ZONA}')::date`;

const consulta = (sql, replacements = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT });
const num = (v) => Number(v || 0);
const fecha = (d) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d).slice(0, 10));

async function config() {
  return {
    diasGracia: Math.max(0, Number(await ConfiguracionService.obtener('LIQUIDACIONDIASGRACIA', 7)) || 0),
    cuenta: String((await ConfiguracionService.obtener('LIQUIDACIONCUENTA', '')) || ''),
  };
}

async function fijarConfig(cambios, { transaction } = {}) {
  const actual = await config();
  const hechos = {};
  if (cambios.diasGracia !== undefined && Number(cambios.diasGracia) !== actual.diasGracia) {
    await ConfiguracionService.fijar('LIQUIDACIONDIASGRACIA', Number(cambios.diasGracia), { transaction });
    hechos.diasGracia = Number(cambios.diasGracia);
  }
  if (cambios.cuenta !== undefined && String(cambios.cuenta).trim() !== actual.cuenta) {
    await ConfiguracionService.fijar('LIQUIDACIONCUENTA', String(cambios.cuenta).trim(), { transaction });
    hechos.cuenta = String(cambios.cuenta).trim();
  }
  return hechos;
}

// Semanas de un negocio (las últimas 12 con ventas), con su estado:
//   en_curso (la semana actual), pendiente / vencida (cerrada sin pagar), pagada, sin_cargo (comisión 0)
async function semanas(negocioId) {
  const { diasGracia } = await config();
  const filas = await consulta(`
    WITH s AS (
      SELECT ${SEMANA} AS semana, COUNT(*) AS pedidos, SUM(p.subtotal) AS ventas, SUM(p.comision) AS comision, SUM(p.costoenvio) AS envios
        FROM tpedidos p
       WHERE p.fhasta = ${VIGENTE} AND p.cnegocio = :n AND p.cestatuspedido IN (:vendidos)
       GROUP BY 1)
    SELECT s.*, l.comision AS pagado, l.fpago, l.referencia,
           s.semana = ${ESTASEMANA} AS actual,
           s.semana + (7 + :dias) <= ${HOY} AS vencida
      FROM s LEFT JOIN tliquidaciones l ON l.cnegocio = :n AND l.semana = s.semana
     ORDER BY s.semana DESC LIMIT 12`, { n: negocioId, vendidos: VENDIDOS, dias: diasGracia });

  return filas.map((f) => {
    const comision = num(f.pagado ?? f.comision);
    const estado = f.pagado != null ? 'pagada' : f.actual ? 'en_curso' : comision === 0 ? 'sin_cargo' : f.vencida ? 'vencida' : 'pendiente';
    const desde = fecha(f.semana);
    const hasta = new Date(`${desde}T12:00:00Z`);
    hasta.setUTCDate(hasta.getUTCDate() + 6);
    const vence = new Date(`${desde}T12:00:00Z`);
    vence.setUTCDate(vence.getUTCDate() + 7 + diasGracia);
    return {
      semana: desde,
      hasta: fecha(hasta),
      pedidos: Number(f.pedidos),
      ventas: num(f.ventas),
      comision,
      recibeNegocio: Number((num(f.ventas) - comision).toFixed(2)),
      estado,
      ...(['pendiente', 'vencida'].includes(estado) && { vence: fecha(vence) }),
      ...(f.pagado != null && { fechaPago: f.fpago, referencia: f.referencia }),
    };
  });
}

// Estado de cuenta del negocio: sus semanas, cuánto debe, si ya está bloqueado y a dónde transferir
async function estadoDeCuenta(negocioId) {
  const lista = await semanas(negocioId);
  const { diasGracia, cuenta } = await config();
  const porPagar = lista.filter((s) => s.estado === 'pendiente' || s.estado === 'vencida');
  return {
    semanas: lista,
    saldoPendiente: Number(porPagar.reduce((t, s) => t + s.comision, 0).toFixed(2)),
    bloqueado: porPagar.some((s) => s.estado === 'vencida'),
    diasGracia,
    cuenta,
  };
}

// Negocios con alguna semana vencida sin pagar (no reciben pedidos). Con "ids" se limita a esos.
async function conDeudaVencida(ids) {
  const { diasGracia } = await config();
  if (ids && !ids.length) return new Set();
  const filas = await consulta(`
    SELECT DISTINCT p.cnegocio AS id
      FROM tpedidos p
     WHERE p.fhasta = ${VIGENTE} AND p.cestatuspedido IN (:vendidos) AND p.comision > 0
       AND ${SEMANA} + (7 + :dias) <= ${HOY}
       ${ids ? 'AND p.cnegocio IN (:ids)' : ''}
       AND NOT EXISTS (SELECT 1 FROM tliquidaciones l WHERE l.cnegocio = p.cnegocio AND l.semana = ${SEMANA})`,
  { vendidos: VENDIDOS, dias: diasGracia, ...(ids && { ids }) });
  return new Set(filas.map((f) => String(f.id)));
}

// Administrador: negocios que deben semanas cerradas, con el saldo y si ya están bloqueados
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
           BOOL_OR(s.semana + (7 + :dias) <= ${HOY}) AS bloqueado, MIN(s.semana) AS desde
      FROM s
      JOIN tnegocios n ON n.cnegocio = s.cnegocio AND n.fhasta = ${VIGENTE}
     WHERE s.semana < ${ESTASEMANA}
       AND NOT EXISTS (SELECT 1 FROM tliquidaciones l WHERE l.cnegocio = s.cnegocio AND l.semana = s.semana)
     GROUP BY n.cnegocio, n.nombre
     ORDER BY bloqueado DESC, saldo DESC`, { vendidos: VENDIDOS, dias: diasGracia });
  return filas.map((f) => ({ negocioId: Number(f.id), nombre: f.nombre, semanas: Number(f.semanas), saldo: num(f.saldo), bloqueado: f.bloqueado, desde: fecha(f.desde) }));
}

// Administrador: registra el pago de una semana cerrada (guarda la foto de lo cobrado) y le avisa al negocio
async function registrarPago(admin, negocioId, { semana, referencia }, req) {
  const s = (await semanas(negocioId)).find((x) => x.semana === semana);
  if (!s) throw AppError.notFound('Ese negocio no tiene ventas en esa semana', 'SEMANANOENCONTRADA');
  if (s.estado === 'pagada') throw AppError.conflict('Esa semana ya está pagada', 'YAPAGADA');
  if (s.estado === 'en_curso') throw AppError.conflict('La semana todavía no termina: se liquida desde el lunes', 'SEMANAENCURSO');
  if (s.estado === 'sin_cargo') throw AppError.conflict('Esa semana no tiene comisión que cobrar', 'SINCOMISION');
  try {
    await sequelize.query(
      `INSERT INTO tliquidaciones (cnegocio, semana, pedidos, ventas, comision, referencia, cusuario)
       VALUES (:n, :semana, :pedidos, :ventas, :comision, :referencia, :admin)`,
      { replacements: { n: negocioId, semana, pedidos: s.pedidos, ventas: s.ventas, comision: s.comision, referencia: referencia?.trim() || null, admin: admin.id } },
    );
  } catch (e) {
    if (e.name === 'SequelizeUniqueConstraintError' || /iukliquidaciones/i.test(e.message)) throw AppError.conflict('Esa semana ya está pagada', 'YAPAGADA');
    throw e;
  }
  auditar({ usuarioId: admin.id, accion: 'LIQUIDACIONPAGADA', entidad: 'NEGOCIOS', entidadId: negocioId, detalle: { semana, comision: s.comision, referencia: referencia || null }, req });
  const [dueno] = await consulta(`SELECT cusuario FROM tnegocios WHERE cnegocio = :n AND fhasta = ${VIGENTE}`, { n: negocioId });
  await NotificacionService.notificar({
    io: req.io, usuarioId: dueno?.cusuario, tipo: 'liquidacion_pagada', titulo: 'Recibimos tu pago ✅',
    mensaje: `Registramos tu pago de $${s.comision.toFixed(2)} de la comisión de la semana del ${s.semana}. ¡Gracias!`,
  });
  return estadoDeCuenta(negocioId);
}

module.exports = { config, fijarConfig, semanas, estadoDeCuenta, conDeudaVencida, pendientes, registrarPago };
