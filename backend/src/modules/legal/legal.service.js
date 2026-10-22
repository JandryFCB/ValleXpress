const fs = require('fs');
const path = require('path');
const { QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const AppError = require('../../shared/errors/AppError');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const Correo = require('../../shared/services/correo.service');
const { ROLAAPI } = require('../../shared/constants/codigos');

// DOCUMENTOS LEGALES: términos de cada perfil y política de privacidad.
//   * El texto vive en backend/legal/<documento>.md (versionado en git). La cabecera trae título, versión, vigencia
//     y un resumen de los cambios. Para publicar una versión nueva basta con editar el .md y subir su "version":
//     a cada usuario se le pide aceptarla al volver a entrar a la app.
//   * Los valores que dependen de la configuración (comisión, zona, tarifas, plazos, correo de soporte) se escriben
//     como {{nombre}} y se completan con los vigentes.
//   * La prueba de la aceptación queda en TACEPTACIONESLEGALES (documento, versión, fecha, IP y plataforma).
//   * El mismo texto se sirve a la app (en bloques listos para dibujar) y como página web pública (/legal/...),
//     que es la que se publica en Google Play.

const CARPETA = path.join(__dirname, '../../../legal');
const IDS = ['terminos-cliente', 'terminos-vendedor', 'terminos-repartidor', 'privacidad'];
const ipDe = (req) => (req?.ip ? String(req.ip).replace(/^::ffff:/, '') : null);

// --- Lectura de los .md (una vez: cambian solo con un despliegue) ---
function leerArchivo(id) {
  const crudo = fs.readFileSync(path.join(CARPETA, `${id}.md`), 'utf8').replace(/\r\n/g, '\n');
  const m = crudo.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!m) throw new Error(`legal/${id}.md no tiene cabecera`);
  const cabecera = Object.fromEntries(m[1].split('\n').map((l) => l.match(/^(\w+):\s*(.*)$/)).filter(Boolean).map((x) => [x[1], x[2].trim()]));
  return { id, titulo: cabecera.titulo, version: String(cabecera.version), vigencia: cabecera.vigencia, resumen: cabecera.resumen || '', texto: m[2].trim() };
}
const DOCUMENTOS = Object.fromEntries(IDS.map((id) => [id, leerArchivo(id)]));

function exigirDocumento(id) {
  const d = DOCUMENTOS[id];
  if (!d) throw AppError.notFound('Ese documento no existe', 'DOCUMENTONOENCONTRADO');
  return d;
}

// "2026-11-01" -> "noviembre de 2026"
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const inicioCobro = (f) => `${MESES[Number(f.slice(5, 7)) - 1] || 'noviembre'} de ${f.slice(0, 4)}`;

// Valores vigentes que se insertan en los textos
async function valores() {
  const dinero = (v) => `$${Number(v).toFixed(2)}`;
  const c = (clave, defecto) => ConfiguracionService.obtener(clave, defecto);
  return {
    correo: Correo.soporte() || 'el correo de soporte indicado en la app',
    cuotaVendedor: dinero(await c('SUSCRIPCIONVENDEDOR', 10)),
    cuotaRepartidor: dinero(await c('SUSCRIPCIONREPARTIDOR', 10)),
    diaPago: String(Number(await c('SUSCRIPCIONDIASGRACIA', 5))),
    inicioCobro: inicioCobro(String(await c('SUSCRIPCIONINICIO', '2026-11-01'))),
    zona: String(await c('ZONANOMBRE', 'Yantzaza')),
    envioBase: dinero(await c('ENVIOBASE', 1)),
    envioPorKm: dinero(await c('ENVIOPORKM', 0.3)),
    venceSinRepartidor: String(Number(await c('PEDIDOVENCESINREPARTIDORMIN', 60))),
    vencePendiente: String(Number(await c('PEDIDOVENCEPENDIENTEMIN', 30))),
    venceTransferencia: String(Number(await c('PEDIDOVENCETRANSFERENCIAMIN', 30))),
  };
}
const completar = (texto, v) => texto.replace(/\{\{(\w+)\}\}/g, (_, k) => v[k] ?? '');

// --- Markdown sencillo -> bloques ---
// Admite: "## Título", párrafos, listas con "- " o "1. " (un nivel de sublista con 2 espacios), texto indentado
// que continúa el punto anterior, y **negrita** dentro del texto (queda tal cual: la app y la web la dibujan).
//   [{ tipo: 'titulo', texto }, { tipo: 'parrafo', texto }, { tipo: 'lista', ordenada, items: [{ texto, sub: [], notas: [] }] }]
function aBloques(md) {
  const bloques = [];
  let parrafo = [];
  let lista = null;
  const cerrarParrafo = () => { if (parrafo.length) { bloques.push({ tipo: 'parrafo', texto: parrafo.join(' ') }); parrafo = []; } };
  const cerrarLista = () => { if (lista) { bloques.push(lista); lista = null; } };

  for (const linea of md.split('\n')) {
    const item = linea.match(/^(\s*)(-|\d+\.)\s+(.*)$/);
    if (!linea.trim()) { cerrarParrafo(); continue; }
    if (/^##\s+/.test(linea)) { cerrarParrafo(); cerrarLista(); bloques.push({ tipo: 'titulo', texto: linea.replace(/^##\s+/, '').trim() }); continue; }
    if (item) {
      cerrarParrafo();
      const [, sangria, marca, texto] = item;
      if (sangria.length >= 2 && lista?.items.length) { lista.items[lista.items.length - 1].sub.push(texto.trim()); continue; }
      const ordenada = marca !== '-';
      if (!lista || lista.ordenada !== ordenada) { cerrarLista(); lista = { tipo: 'lista', ordenada, items: [] }; }
      lista.items.push({ texto: texto.trim(), sub: [], notas: [] });
      continue;
    }
    if (/^\s{2,}\S/.test(linea) && lista?.items.length) { lista.items[lista.items.length - 1].notas.push(linea.trim()); continue; }
    cerrarLista();
    parrafo.push(linea.trim());
  }
  cerrarParrafo(); cerrarLista();
  return bloques;
}

// --- Para la app ---
async function documento(id) {
  const d = exigirDocumento(id);
  return { id: d.id, titulo: d.titulo, version: d.version, vigencia: d.vigencia, resumen: d.resumen, bloques: aBloques(completar(d.texto, await valores())) };
}

const resumenDe = (d) => ({ id: d.id, titulo: d.titulo, version: d.version, vigencia: d.vigencia, resumen: d.resumen });
const lista = () => IDS.map((id) => resumenDe(DOCUMENTOS[id]));

// Qué documentos debe tener aceptados cada perfil (el administrador no acepta términos)
function requeridos(rolApi) {
  if (!['cliente', 'vendedor', 'repartidor'].includes(rolApi)) return [];
  return [`terminos-${rolApi}`, 'privacidad'];
}

const consulta = (sql, replacements, opciones = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT, ...opciones });

// Documentos cuya versión vigente el usuario todavía no aceptó
async function pendientes(usuario) {
  const ids = requeridos(usuario.tipoUsuario);
  if (!ids.length) return [];
  const aceptados = await consulta('SELECT documento, version FROM taceptacioneslegales WHERE cusuario = :u', { u: usuario.id });
  const tiene = new Set(aceptados.map((a) => `${a.documento}@${a.version}`));
  return ids.filter((id) => !tiene.has(`${id}@${DOCUMENTOS[id].version}`)).map((id) => resumenDe(DOCUMENTOS[id]));
}

async function guardar(usuarioId, ids, req, opciones = {}) {
  for (const id of ids) {
    await sequelize.query(
      `INSERT INTO taceptacioneslegales (cusuario, documento, version, ip, plataforma)
       VALUES (:u, :d, :v, :ip, :p) ON CONFLICT (cusuario, documento, version) DO NOTHING`,
      { replacements: { u: usuarioId, d: id, v: DOCUMENTOS[id].version, ip: ipDe(req), p: String(req?.body?.plataforma || '').slice(0, 20) || null }, ...opciones },
    );
  }
}

// La app manda lo que el usuario leyó y aceptó, con su versión: si mientras tanto se publicó otra, se rechaza
async function aceptar(usuario, documentos, req) {
  const ids = requeridos(usuario.tipoUsuario);
  for (const { id, version } of documentos) {
    if (!ids.includes(id)) throw AppError.badRequest('Ese documento no corresponde a tu perfil', 'DOCUMENTONOCORRESPONDE');
    if (String(version) !== DOCUMENTOS[id].version) throw AppError.conflict('Ese documento se actualizó: vuelve a leerlo', 'VERSIONDESACTUALIZADA');
  }
  await guardar(usuario.id, documentos.map((d) => d.id), req);
  return pendientes(usuario);
}

// Al registrarse: acepta las versiones vigentes de su perfil (dentro de la transacción del registro)
const aceptarAlRegistrarse = (usuarioId, rolApi, req, opciones) => guardar(usuarioId, requeridos(rolApi), req, opciones);

// Para el administrador: versión vigente de cada documento y cuántas cuentas activas ya la aceptaron
async function estadisticas() {
  const totales = await consulta('SELECT rol, COUNT(*) AS total FROM vusuarios WHERE activo GROUP BY rol', {});
  const aceptadas = await consulta(`
    SELECT u.rol, a.documento, a.version, COUNT(*) AS total
      FROM vusuarios u JOIN taceptacioneslegales a ON a.cusuario = u.usuario
     WHERE u.activo
     GROUP BY u.rol, a.documento, a.version`, {});
  const cuentas = (rol) => Number(totales.find((f) => ROLAAPI[f.rol] === rol)?.total || 0);
  const aceptaron = (rol, id) => Number(aceptadas.find((f) => ROLAAPI[f.rol] === rol && f.documento === id && f.version === DOCUMENTOS[id].version)?.total || 0);
  return IDS.map((id) => {
    const roles = id === 'privacidad' ? ['cliente', 'vendedor', 'repartidor'] : [id.slice('terminos-'.length)];
    return {
      ...resumenDe(DOCUMENTOS[id]),
      cuentas: roles.reduce((s, r) => s + cuentas(r), 0),
      aceptaron: roles.reduce((s, r) => s + aceptaron(r, id), 0),
    };
  });
}

const versionDe = (id) => DOCUMENTOS[id]?.version || null;

module.exports = { IDS, versionDe, documento, lista, requeridos, pendientes, aceptar, aceptarAlRegistrarse, estadisticas, aBloques, valores, completar, exigirDocumento };
