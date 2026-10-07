const AppError = require('../../shared/errors/AppError');
const { ESTADOPEDIDO: E, ESTADOPEDIDOAAPI } = require('../../shared/constants/codigos');

// Máquina de estados del pedido (por CÓDIGO del catálogo ESTADOPEDIDO). Define QUÉ transiciones existen y
// QUIÉN puede hacerlas; ningún endpoint puede saltarse el flujo.
//
//   PENDIENTE -> CONFIRMADO -> PREPARANDO -> LISTO -> EN CAMINO -> RECOGIDO -> ENTREGADO -> RECIBIDO
//        |  \-> RECHAZADO (vendedor)           (EN CAMINO: un repartidor aceptó y va al negocio)
//        \----> CANCELADO (cliente, solo mientras está pendiente)
const TRANSICIONES = Object.freeze({
  [E.PENDIENTE]: [E.CONFIRMADO, E.RECHAZADO, E.CANCELADO],
  [E.CONFIRMADO]: [E.PREPARANDO],
  [E.PREPARANDO]: [E.LISTO],
  [E.LISTO]: [E.ENCAMINO],
  [E.ENCAMINO]: [E.RECOGIDO],
  [E.RECOGIDO]: [E.ENTREGADO],
  [E.ENTREGADO]: [E.RECIBIDO],
});

// Quién puede llevar el pedido a cada estado
const QUIEN = Object.freeze({
  [E.CONFIRMADO]: 'vendedor', [E.RECHAZADO]: 'vendedor', [E.PREPARANDO]: 'vendedor', [E.LISTO]: 'vendedor',
  [E.ENCAMINO]: 'repartidor', [E.RECOGIDO]: 'repartidor', [E.ENTREGADO]: 'repartidor',
  [E.RECIBIDO]: 'cliente', [E.CANCELADO]: 'cliente',
});

// Columna de fecha que se completa al entrar a cada estado
const FECHA = Object.freeze({
  [E.CONFIRMADO]: 'fechaConfirmacion', [E.PREPARANDO]: 'fechaPreparacion', [E.LISTO]: 'fechaListo',
  [E.ENCAMINO]: 'fechaAsignacion', [E.RECOGIDO]: 'fechaRecogida', [E.ENTREGADO]: 'fechaEntrega',
  [E.RECIBIDO]: 'fechaRecibido', [E.CANCELADO]: 'fechaCancelado', [E.RECHAZADO]: 'fechaCancelado',
});

const nombre = (codigo) => ESTADOPEDIDOAAPI[codigo] || codigo;

// Lanza el error adecuado si la transición no existe o el rol no puede hacerla
function validarTransicion(actual, siguiente, rol) {
  if (!(TRANSICIONES[actual] || []).includes(siguiente)) {
    throw AppError.conflict(`El pedido está "${nombre(actual)}" y no puede pasar a "${nombre(siguiente)}"`, 'TRANSICIONINVALIDA');
  }
  if (QUIEN[siguiente] !== rol) {
    throw AppError.forbidden('No tienes permiso para realizar este cambio de estado', 'ESTADONOPERMITIDO');
  }
}

// Campos a actualizar al entrar a "siguiente": el estado y su fecha
const cambiosDe = (siguiente) => ({ estado: siguiente, [FECHA[siguiente]]: new Date() });

module.exports = { TRANSICIONES, validarTransicion, cambiosDe };
