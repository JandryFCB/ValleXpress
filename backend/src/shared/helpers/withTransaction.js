const { sequelize } = require('../../config/database');

// Ejecuta fn dentro de una transacción: commit automático si termina bien, rollback si lanza un error.
// Nada de rollback() manual ni "return" a medias.
//
//   await withTransaction(async (t) => {
//     await Usuario.create({ ... }, { transaction: t });
//   }, { usuarioId: req.usuario.id });
//
// Si se pasa usuarioId (el usuario: jcayapa), queda registrado quién hizo el cambio en las tablas HIST (columna CAMBIADOPOR).
module.exports = (fn, { usuarioId } = {}) =>
  sequelize.transaction(async (t) => {
    if (usuarioId) {
      await sequelize.query("SELECT set_config('app.usuario', :id, true)", {
        replacements: { id: String(usuarioId) },
        transaction: t,
      });
    }
    return fn(t);
  });
