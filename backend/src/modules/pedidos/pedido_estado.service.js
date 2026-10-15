const AppError = require('../../shared/errors/AppError');
const { ESTADOPEDIDO: E, ESTADOPEDIDOAAPI } = require('../../shared/constants/codigos');

// Máquina de estados del pedido (por CÓDIGO del catálogo TESTATUSPEDIDO). Define QUÉ transiciones existen y
// QUIÉN puede hacerlas; ningún endpoint puede saltarse el flujo. La fecha de cada paso NO se guarda en columnas:
// sale del historial de TPEDIDOS (cada cambio de estado deja su versión con su FDESDE).
//
//   PENDIENTE -> CONFIRMADO -> PREPARANDO -> LISTO -> EN CAMINO -> RECOGIDO -> ENTREGADO -> RECIBIDO
//        |  \-> RECHAZADO (negocio)            (EN CAMINO: un repartidor aceptó y va al negocio)
//        \----> CANCELADO (cliente, solo mientras está pendiente)
const TRANSICIONES = Object.freeze({
  [E.PENDIENTE]: [E.CONFIRMADO, E.RECHAZADO, E.CANCELADO],
  [E.CONFIRMADO]: [E.PREPARANDO, E.LISTO],
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

// Pedidos "en curso" (los que se muestran como activos) y terminados
const ACTIVOS = Object.freeze([E.PENDIENTE, E.CONFIRMADO, E.PREPARANDO, E.LISTO, E.ENCAMINO, E.RECOGIDO, E.ENTREGADO]);
const TERMINADOS = Object.freeze([E.RECIBIDO, E.RECHAZADO, E.CANCELADO]);

// El administrador puede cancelar un pedido en curso para resolver un problema (el negocio no responde, el
// repartidor no llega...) hasta que se entrega. Va aparte de TRANSICIONES: no es un paso normal del flujo.
const CANCELABLESPORADMIN = Object.freeze([E.PENDIENTE, E.CONFIRMADO, E.PREPARANDO, E.LISTO, E.ENCAMINO, E.RECOGIDO]);

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

function validarCancelacionAdmin(actual) {
  if (!CANCELABLESPORADMIN.includes(actual)) {
    throw AppError.conflict(`El pedido está "${nombre(actual)}": ya no se puede cancelar`, 'TRANSICIONINVALIDA');
  }
}

module.exports = { TRANSICIONES, ACTIVOS, TERMINADOS, CANCELABLESPORADMIN, validarTransicion, validarCancelacionAdmin };
