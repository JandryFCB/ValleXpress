const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const NotificacionService = require('../notificaciones/notificacion.service');
const Notificacion = require('../notificaciones/notificacion.model');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const { auditar, logMensaje } = require('../../shared/services/log.service');
const { ESTADOPEDIDO: E, METODOPAGO } = require('../../shared/constants/codigos');
const PedidoService = require('./pedido.service');
const TransferenciaService = require('./transferencia.service');

// VIGILANTE DE VENCIMIENTOS: ningún pedido queda varado horas o días. Cada minuto revisa:
//   * LISTO o EN CAMINO sin que un repartidor lo recoja (minutos contados desde que quedó LISTO):
//       - a los PEDIDOAVISOSINREPARTIDORMIN: avisa al negocio y a los administradores, y otra vez a los
//         repartidores en línea (una sola vez por pedido).
//       - a los PEDIDOVENCESINREPARTIDORMIN: lo cancela.
//   * PENDIENTE sin respuesta del negocio a los PEDIDOVENCEPENDIENTEMIN: lo cancela.
//   * CONFIRMADO por transferencia sin que el cliente suba el comprobante (o sin subir otro después de que el negocio
//     rechazara el anterior) a los PEDIDOVENCETRANSFERENCIAMIN: lo cancela.
// Al cancelar vuelve el stock y avisan al cliente, al negocio y al repartidor. Queda en la auditoría como "sistema".
const SISTEMA = 'sistema';
const CADAMS = Number(process.env.VENCIMIENTO_CADA_MS) || 60 * 1000;     // las pruebas lo bajan para no esperar
const VIGENTE = "'2999-12-31 00:00:00-05'";

const minutos = async (clave, porDefecto) => Math.max(1, Number(await ConfiguracionService.obtener(clave, porDefecto)) || porDefecto);

async function candidatos() {
  return sequelize.query(
    `SELECT p.cpedido AS id, p.cestatuspedido AS estado, p.fpedido AS pedido, p.cnegocio AS negocio, p.cusuario_repartidor AS repartidor,
            n.nombre AS "negocioNombre", n.cusuario AS dueno,
            (SELECT MIN(h.fdesde) FROM tpedidos h WHERE h.cpedido = p.cpedido AND h.cestatuspedido = :listo) AS listo,
            (SELECT MIN(h.fdesde) FROM tpedidos h WHERE h.cpedido = p.cpedido AND h.cestatuspedido = :confirmado) AS confirmado
       FROM tpedidos p
       JOIN tnegocios n ON n.cnegocio = p.cnegocio AND n.fhasta = ${VIGENTE}
      WHERE p.fhasta = ${VIGENTE}
        AND (p.cestatuspedido IN (:estados) OR (p.cestatuspedido = :confirmado AND p.cmetodopago = :transferencia AND NOT p.espagado))`,
    {
      replacements: { listo: E.LISTO, confirmado: E.CONFIRMADO, transferencia: METODOPAGO.TRANSFERENCIA, estados: [E.PENDIENTE, E.LISTO, E.ENCAMINO] },
      type: QueryTypes.SELECT,
    },
  );
}

// Aviso de "nadie lo ha recogido": una sola vez por pedido (la BD lo recuerda aunque el servidor se reinicie)
async function avisarDemora(p, minutosListo, vence, io) {
  if (await Notificacion.count({ where: { pedidoId: p.id, tipo: 'pedido_sin_repartidor' } })) return false;
  const faltan = Math.max(1, vence - minutosListo);
  const aviso = { io, tipo: 'pedido_sin_repartidor', titulo: 'Pedido esperando repartidor ⏳', pedidoId: p.id, datos: { estado: 'listo' } };
  await NotificacionService.notificar({
    ...aviso, usuarioId: p.dueno,
    mensaje: `Ningún repartidor ha recogido el pedido #${p.id} todavía. Si nadie lo recoge en ${faltan} min se cancelará solo`,
  });
  await NotificacionService.notificarAdministradores({ ...aviso, mensaje: `${p.negocioNombre}: el pedido #${p.id} lleva ${minutosListo} min listo sin repartidor` });
  if (p.estado === E.LISTO) await PedidoService.avisarRepartidores(io, { id: p.id, costoEnvio: await costoEnvio(p.id) }, p.negocioNombre);
  return true;
}

async function costoEnvio(id) {
  const [f] = await sequelize.query(`SELECT costoenvio FROM tpedidos WHERE cpedido = :id AND fhasta = ${VIGENTE}`, { replacements: { id }, type: QueryTypes.SELECT });
  return f?.costoenvio ?? 0;
}

async function cancelar(p, motivo, io, siSigue) {
  const cancelado = await PedidoService.cancelarEnCurso(p.id, {
    motivoGuardado: `Cancelado automáticamente: ${motivo}`, motivoAviso: motivo, usuarioId: SISTEMA, io, soloSi: [p.estado], siSigue,
  });
  if (cancelado) auditar({ usuarioId: SISTEMA, accion: 'PEDIDOVENCIDO', entidad: 'PEDIDOS', entidadId: p.id, detalle: { estado: p.estado, motivo } });
  return !!cancelado;
}

// Una pasada. "ahora" se puede adelantar en las pruebas para no esperar una hora de verdad.
async function revisar({ io, ahora = new Date() } = {}) {
  const [aviso, vence, vencePendiente, venceTransferencia] = await Promise.all([
    minutos('PEDIDOAVISOSINREPARTIDORMIN', 30), minutos('PEDIDOVENCESINREPARTIDORMIN', 60), minutos('PEDIDOVENCEPENDIENTEMIN', 30),
    minutos('PEDIDOVENCETRANSFERENCIAMIN', 30),
  ]);
  const resultado = { avisados: [], cancelados: [] };
  for (const p of await candidatos()) {
    p.id = Number(p.id);
    try {
      if (p.estado === E.PENDIENTE) {
        const m = Math.floor((ahora - new Date(p.pedido)) / 60000);
        if (m >= vencePendiente && (await cancelar(p, `${p.negocioNombre} no respondió a tiempo`, io))) resultado.cancelados.push(p.id);
        continue;
      }
      if (p.estado === E.CONFIRMADO) {
        // Sin pago en camino desde que se confirmó (o desde que el negocio rechazó el último comprobante)
        const c = await TransferenciaService.ultimo(p.id);
        if (c && c.estado !== 'RECHAZADO') continue;
        const desde = new Date(c?.frevision || p.confirmado);
        const m = Math.floor((ahora - desde) / 60000);
        const sigueSinPago = async (actual, t) => TransferenciaService.sinPagoEnCamino(actual, await TransferenciaService.ultimo(actual.id, { transaction: t }));
        if (m >= venceTransferencia && (await cancelar(p, 'no recibimos el comprobante de la transferencia a tiempo', io, sigueSinPago))) resultado.cancelados.push(p.id);
        continue;
      }
      if (!p.listo) continue;
      const m = Math.floor((ahora - new Date(p.listo)) / 60000);
      if (m >= vence) {
        if (await cancelar(p, 'ningún repartidor lo recogió a tiempo', io)) resultado.cancelados.push(p.id);
      } else if (m >= aviso && (await avisarDemora(p, m, vence, io))) {
        resultado.avisados.push(p.id);
      }
    } catch (e) {
      logMensaje({ nivel: 'ADVERTENCIA', modulo: 'PEDIDOS', accion: 'VENCIMIENTOFALLIDO', mensaje: 'No se pudo revisar el vencimiento de un pedido', detalle: { error: e.message }, pedidoId: p.id });
    }
  }
  return resultado;
}

// Arranca el vigilante (una pasada al iniciar y luego cada minuto). No impide que el proceso termine.
function iniciar(io) {
  let ocupado = false;
  const pasada = async () => {
    if (ocupado) return;
    ocupado = true;
    try {
      const r = await revisar({ io });
      if (r.cancelados.length || r.avisados.length) console.log(`⏳ Vencimientos: cancelados ${r.cancelados.join(', ') || '-'} · avisados ${r.avisados.join(', ') || '-'}`);
    } catch (e) {
      logMensaje({ nivel: 'ADVERTENCIA', modulo: 'PEDIDOS', accion: 'VENCIMIENTOFALLIDO', mensaje: 'Falló la revisión de vencimientos', detalle: { error: e.message } });
    } finally {
      ocupado = false;
    }
  };
  pasada();
  return setInterval(pasada, CADAMS).unref();
}

module.exports = { revisar, iniciar };
