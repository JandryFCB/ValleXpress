const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const ArchivoService = require('../../shared/services/archivo.service');
const { ESTADOPEDIDO: E, METODOPAGO } = require('../../shared/constants/codigos');

// PAGO POR TRANSFERENCIA del cliente al negocio. ValleXpress no toca el dinero: muestra las cuentas del negocio,
// guarda la foto del comprobante y el negocio confirma si le llegó.
//   * El cliente solo puede elegir transferencia si el negocio tiene al menos una cuenta.
//   * Las cuentas y el comprobante se habilitan cuando el negocio CONFIRMA el pedido: así nadie paga un pedido que
//     el negocio no puede atender.
//   * Mientras no esté pagado, el negocio no puede pasarlo a "preparando" ni a "listo".
//   * Sin comprobante (o con el último rechazado), el negocio puede rechazar el pedido y el cliente cancelarlo.

const MAXCUENTAS = 5;
const TIPOS = ['ahorros', 'corriente'];
const consulta = (sql, replacements = {}, opciones = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT, ...opciones });

const esTransferencia = (p) => p.metodoPago === METODOPAGO.TRANSFERENCIA;

// ---------------------------------------------------------------------------------------------
// Cuentas del negocio
// ---------------------------------------------------------------------------------------------
async function cuentas(negocioId, opciones = {}) {
  const filas = await consulta(
    'SELECT banco, tipo, numero, titular, identificacion FROM tnegociocuentas WHERE cnegocio = :n ORDER BY numerolinea',
    { n: negocioId }, opciones,
  );
  return filas.map((f) => ({ banco: f.banco, tipo: f.tipo, numero: f.numero, titular: f.titular, identificacion: f.identificacion || '' }));
}

// Negocios (de la lista) que reciben transferencias
async function conCuentas(ids) {
  if (!ids.length) return new Set();
  const filas = await consulta('SELECT DISTINCT cnegocio FROM tnegociocuentas WHERE cnegocio IN (:ids)', { ids });
  return new Set(filas.map((f) => String(f.cnegocio)));
}

// Reemplaza la lista completa de cuentas del negocio
async function fijarCuentas(negocioId, lista, usuarioId) {
  const limpias = (Array.isArray(lista) ? lista : [])
    .map((c) => ({
      banco: String(c?.banco ?? '').trim(),
      tipo: TIPOS.includes(String(c?.tipo ?? '').trim()) ? String(c.tipo).trim() : 'ahorros',
      numero: String(c?.numero ?? '').replace(/[\s-]+/g, ''),     // sin espacios ni guiones
      titular: String(c?.titular ?? '').trim(),
      identificacion: String(c?.identificacion ?? '').trim(),
    }))
    .filter((c) => c.banco || c.numero || c.titular);
  if (limpias.length > MAXCUENTAS) throw AppError.badRequest(`Puedes registrar hasta ${MAXCUENTAS} cuentas`, 'DEMASIADASCUENTAS');
  for (const c of limpias) {
    if (!c.banco || !c.numero || !c.titular) throw AppError.badRequest('Cada cuenta necesita banco, número y titular', 'CUENTAINCOMPLETA');
    if (c.banco.length > 80 || c.titular.length > 120) throw AppError.badRequest('El banco o el titular es muy largo', 'CUENTAINVALIDA');
    if (!/^\d{4,30}$/.test(c.numero)) throw AppError.badRequest(`El número de cuenta de ${c.banco} solo lleva dígitos`, 'CUENTAINVALIDA');
    if (c.identificacion && !/^\d{10}(\d{3})?$/.test(c.identificacion)) throw AppError.badRequest('La cédula o RUC del titular tiene 10 o 13 dígitos', 'CUENTAINVALIDA');
  }
  await withTransaction(async (t) => {
    await sequelize.query('DELETE FROM tnegociocuentas WHERE cnegocio = :n', { replacements: { n: negocioId }, transaction: t });
    for (const [i, c] of limpias.entries()) {
      await sequelize.query(
        `INSERT INTO tnegociocuentas (cnegocio, numerolinea, banco, tipo, numero, titular, identificacion, cusuario_registro)
         VALUES (:n, :linea, :banco, :tipo, :numero, :titular, NULLIF(:identificacion, ''), :u)`,
        { replacements: { n: negocioId, linea: i + 1, ...c, u: usuarioId }, transaction: t },
      );
    }
  }, { usuarioId });
  return cuentas(negocioId);
}

// ---------------------------------------------------------------------------------------------
// Comprobantes del pedido
// ---------------------------------------------------------------------------------------------
// El último comprobante de cada pedido (el que cuenta)
async function ultimos(pedidoIds, opciones = {}) {
  if (!pedidoIds.length) return new Map();
  const filas = await consulta(`
    SELECT DISTINCT ON (cpedido) ccomprobante AS id, cpedido, carchivo, referencia, estado, motivorechazo, fcreacion, frevision
      FROM tpedidocomprobantes WHERE cpedido IN (:ids)
     ORDER BY cpedido, fcreacion DESC, ccomprobante DESC`, { ids: pedidoIds }, opciones);
  return new Map(filas.map((f) => [String(f.cpedido), f]));
}
const ultimo = async (pedidoId, opciones) => (await ultimos([pedidoId], opciones)).get(String(pedidoId)) || null;

// ¿Puede el cliente subir el comprobante ahora? (confirmado, sin pagar y sin uno en revisión)
const puedeSubir = (p, c) => esTransferencia(p) && !p.pagado && p.estado === E.CONFIRMADO && c?.estado !== 'ENVIADO';

// ¿El pedido sigue sin pago en camino? (sin comprobante o con el último rechazado): se puede rechazar o cancelar
const sinPagoEnCamino = (p, c) => esTransferencia(p) && !p.pagado && (!c || c.estado === 'RECHAZADO');

// Lo que la app recibe del pago por transferencia de cada pedido. Las cuentas solo las ve el cliente (y el admin)
// mientras tenga que pagar; el comprobante lo ven el cliente, el negocio y el administrador.
async function paraApi(pedidos, req, rol) {
  const trans = pedidos.filter(esTransferencia);
  const salida = new Map();
  if (!trans.length || !['cliente', 'vendedor', 'administrador'].includes(rol)) return salida;
  const comp = await ultimos(trans.map((p) => Number(p.id)));
  const urls = await ArchivoService.mapaUrls(req, [...comp.values()].map((c) => c.carchivo));
  const cuentasDe = new Map();
  for (const p of trans) {
    const c = comp.get(String(p.id)) || null;
    const ver = rol !== 'vendedor' && puedeSubir(p, c);
    if (ver && !cuentasDe.has(String(p.negocioId))) cuentasDe.set(String(p.negocioId), await cuentas(p.negocioId));
    salida.set(String(p.id), {
      cuentas: ver ? cuentasDe.get(String(p.negocioId)) : [],
      puedeSubir: puedeSubir(p, c),
      comprobante: c && {
        id: Number(c.id),
        estado: String(c.estado).toLowerCase(),
        imagen: urls[String(c.carchivo)]?.url || null,
        referencia: c.referencia,
        motivo: c.motivorechazo,
        fecha: c.fcreacion,
        revisado: c.frevision,
      },
    });
  }
  return salida;
}

module.exports = { MAXCUENTAS, esTransferencia, cuentas, conCuentas, fijarCuentas, ultimo, ultimos, puedeSubir, sinPagoEnCamino, paraApi };
