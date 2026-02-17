// backend/src/services/pedido_estado.service.js

const ESTADOS = Object.freeze({
  PENDIENTE: 'pendiente',
  CONFIRMADO: 'confirmado',
  PREPARANDO: 'preparando',
  LISTO: 'listo',
  EN_CAMINO: 'en_camino',
  ENTREGADO: 'entregado',
  RECIBIDO_CLIENTE: 'recibido_cliente',
  CANCELADO: 'cancelado',
});

const TRANSICIONES = Object.freeze({
  [ESTADOS.PENDIENTE]: [ESTADOS.CONFIRMADO, ESTADOS.CANCELADO],
  [ESTADOS.CONFIRMADO]: [ESTADOS.PREPARANDO, ESTADOS.CANCELADO],
  [ESTADOS.PREPARANDO]: [ESTADOS.LISTO],
  [ESTADOS.LISTO]: [ESTADOS.EN_CAMINO],
  [ESTADOS.EN_CAMINO]: [ESTADOS.ENTREGADO],
  [ESTADOS.ENTREGADO]: [ESTADOS.RECIBIDO_CLIENTE],
  [ESTADOS.RECIBIDO_CLIENTE]: [],
  [ESTADOS.CANCELADO]: [],
});

const ROLES_PUEDEN_LLEGAR_A = Object.freeze({
  [ESTADOS.CONFIRMADO]: ['vendedor'],
  [ESTADOS.PREPARANDO]: ['vendedor'],
  [ESTADOS.LISTO]: ['vendedor'],
  [ESTADOS.EN_CAMINO]: ['repartidor'],
  [ESTADOS.ENTREGADO]: ['repartidor'],
  [ESTADOS.RECIBIDO_CLIENTE]: ['cliente'],
  [ESTADOS.CANCELADO]: ['cliente'],
});

function puedeTransicionar(actual, siguiente) {
  return (TRANSICIONES[actual] || []).includes(siguiente);
}

function rolPuedeCambiarA(rol, siguiente) {
  return (ROLES_PUEDEN_LLEGAR_A[siguiente] || []).includes(rol);
}

function buildUpdatesPorEstado(estado) {
  const now = new Date();
  const updates = { estado };

  if (estado === ESTADOS.CONFIRMADO) updates.fechaConfirmacion = now;
  if (estado === ESTADOS.PREPARANDO) updates.fechaPreparacion = now;
  if (estado === ESTADOS.LISTO) updates.fechaListo = now;
  if (estado === ESTADOS.EN_CAMINO) updates.fechaRecogida = now;
  if (estado === ESTADOS.ENTREGADO) updates.fechaEntrega = now;

  return updates;
}

module.exports = {
  ESTADOS,
  puedeTransicionar,
  rolPuedeCambiarA,
  buildUpdatesPorEstado,
};
