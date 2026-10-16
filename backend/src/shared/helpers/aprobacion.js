const AppError = require('../errors/AppError');
const withTransaction = require('./withTransaction');
const { auditar } = require('../services/log.service');
const Correo = require('../services/correo.service');
const { APROBACION, APROBACIONAAPI } = require('../constants/codigos');

// Aprobación de un negocio o un repartidor, vista por su dueño: el estado, el motivo y, mientras no esté
// aprobado, a quién escribir (la app lo muestra en la pantalla de "cuenta en revisión").
const datosAprobacion = (fila) => ({
  aprobacion: APROBACIONAAPI[fila.aprobacion],
  motivoAprobacion: fila.motivoAprobacion || null,
  ...(fila.aprobacion !== APROBACION.APROBADO && { soporte: Correo.soporte() }),
});

// Un negocio o repartidor RECHAZADO corrige sus datos y vuelve a la fila de revisión del administrador.
// Uno suspendido no: eso lo decide el administrador (debe escribir a soporte).
async function pedirRevision(fila, { usuarioId, entidad, entidadId, req }) {
  if (fila.aprobacion === APROBACION.PENDIENTE) throw AppError.conflict('Tu solicitud ya está en revisión', 'YAENREVISION');
  if (fila.aprobacion !== APROBACION.RECHAZADO) {
    throw AppError.conflict('Solo una solicitud rechazada puede pedir una nueva revisión', 'REVISIONNOPERMITIDA');
  }
  await withTransaction((t) => fila.update({ aprobacion: APROBACION.PENDIENTE, motivoAprobacion: null }, { transaction: t }), { usuarioId });
  auditar({ usuarioId, accion: 'REVISIONSOLICITADA', entidad, entidadId, req });
}

module.exports = { datosAprobacion, pedirRevision };
