// Pone (o cambia) la clave del ADMINISTRADOR (usuario "admin"). La migración 001 lo crea con la clave '!', que
// ningún hash acepta: hasta correr este script nadie puede entrar como administrador.
//   CLAVE="una-clave-segura" npm run admin:clave
// Cierra las sesiones abiertas del administrador (la clave vieja deja de servir) y queda en la auditoría.
require('dotenv').config();
const { sequelize } = require('../src/config/database');
const UsuarioCuenta = require('../src/modules/auth/usuarioCuenta.model');
const SesionService = require('../src/shared/services/sesion.service');
const withTransaction = require('../src/shared/helpers/withTransaction');
const { hashClave } = require('../src/shared/utils/clave');
const { auditar } = require('../src/shared/services/log.service');

(async () => {
  const clave = process.env.CLAVE || '';
  if (clave.length < 8) {
    console.error('Indica la clave nueva (mínimo 8 caracteres) en la variable CLAVE.');
    process.exit(1);
  }
  const claveHash = await hashClave(clave);
  await withTransaction(async (t) => {
    const [filas] = await UsuarioCuenta.update({ claveHash, claveCambiadaEn: new Date() }, { where: { id: 'admin' }, transaction: t });
    if (!filas) throw new Error('No existe el usuario "admin": ¿se aplicaron las migraciones?');
    await SesionService.cerrarTodas('admin', 'CLAVE', { transaction: t });
  }, { usuarioId: 'admin' });
  await auditar({ usuarioId: 'admin', accion: 'CAMBIOCLAVE', entidad: 'USUARIOS', entidadId: 'admin', detalle: { origen: 'script clave-admin' } });
  console.log('Listo: el administrador ya puede entrar con el usuario "admin" y la clave indicada.');
  await sequelize.close();
})().catch(async (e) => {
  console.error('No se pudo cambiar la clave:', e.message);
  await sequelize.close().catch(() => {});
  process.exit(1);
});
