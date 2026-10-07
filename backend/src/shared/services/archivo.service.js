const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const sharp = require('sharp');
const Archivo = require('../../modules/archivos/archivo.model');
const AppError = require('../errors/AppError');

// Imágenes: llegan en base64 (como las envía la app), se validan, se optimizan a WebP en 3 tamaños, se guardan
// en disco (backend/uploads) y su metadato en la tabla ARCHIVOS. La BD solo guarda el código (ARC-000001).
//   * Se valida el contenido REAL con sharp (no el tipo que diga el cliente): solo JPEG, PNG y WebP.
//   * Se corrige la orientación y se eliminan los metadatos (EXIF/GPS) por privacidad.
//   * El nombre del archivo es su hash SHA-256: la misma imagen subida dos veces se guarda una sola vez.
//   * No se conserva el archivo original subido (ahorra espacio): "rutaoriginal" apunta a la versión optimizada.

// UPLOADS_DIR permite cambiar la carpeta (las pruebas usan una temporal para no ensuciar backend/uploads)
const RAIZ = process.env.UPLOADS_DIR || path.join(__dirname, '../../../uploads');
const MAXBYTES = 8 * 1024 * 1024;
const FORMATOS = new Set(['jpeg', 'png', 'webp']);

// Tamaño máximo por tipo de imagen (la miniatura y la mediana son iguales para todos)
const PERFILES = {
  PERFIL: { w: 512, h: 512, fit: 'cover' },
  LOGO: { w: 512, h: 512, fit: 'cover' },
  BANNER: { w: 1600, h: 600, fit: 'cover' },
  PRODUCTO: { w: 1200, h: 1200, fit: 'inside' },
  DOCUMENTO: { w: 2000, h: 2000, fit: 'inside' },
  EVIDENCIA: { w: 2000, h: 2000, fit: 'inside' },
  OTRO: { w: 1200, h: 1200, fit: 'inside' },
};

function decodificar(texto) {
  if (typeof texto !== 'string' || !texto.trim()) throw AppError.badRequest('No se proporcionó la imagen', 'IMAGENVACIA');
  const limpio = texto.replace(/^data:[^;,]+;base64,/, '').replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(limpio)) throw AppError.badRequest('La imagen no es válida', 'IMAGENINVALIDA');
  if (limpio.length * 0.75 > MAXBYTES) throw new AppError('La imagen supera los 8 MB', 413, 'IMAGENMUYGRANDE');
  return Buffer.from(limpio, 'base64');
}

async function procesar(buffer, categoria) {
  const cfg = PERFILES[categoria] || PERFILES.OTRO;
  try {
    const meta = await sharp(buffer, { limitInputPixels: 40e6 }).metadata();     // lanza si no es una imagen
    if (!FORMATOS.has(meta.format)) throw new Error('formato no permitido');
    const base = () => sharp(buffer, { limitInputPixels: 40e6 }).rotate();      // rotate() aplica la orientación EXIF
    const principal = await base()
      .resize({ width: cfg.w, height: cfg.h, fit: cfg.fit, withoutEnlargement: true })
      .webp({ quality: 80 }).toBuffer({ resolveWithObject: true });
    const mediana = await base().resize({ width: 800, height: 800, fit: 'inside', withoutEnlargement: true }).webp({ quality: 75 }).toBuffer();
    const miniatura = await base().resize({ width: 200, height: 200, fit: 'inside', withoutEnlargement: true }).webp({ quality: 70 }).toBuffer();
    return { principal, mediana, miniatura };
  } catch {
    throw AppError.badRequest('La imagen no es válida o está dañada (solo JPEG, PNG o WebP)', 'IMAGENINVALIDA');
  }
}

async function escribir(ruta, datos) {
  await fs.mkdir(path.dirname(ruta), { recursive: true });
  await fs.writeFile(ruta, datos);
}

// Guarda una imagen recibida en base64 y devuelve la fila de ARCHIVOS (con su código en .id)
async function guardarBase64({ base64, categoria, propietario, nombreOriginal = null }) {
  const { principal, mediana, miniatura } = await procesar(decodificar(base64), categoria);
  const hash = crypto.createHash('sha256').update(principal.data).digest('hex');

  const existente = await Archivo.findOne({ where: { hash, categoria } });
  if (existente) return existente;                                   // misma imagen: no se duplica

  const carpeta = categoria.toLowerCase();
  const nombre = hash.slice(0, 24);
  const rel = (sufijo) => `uploads/${carpeta}/${nombre}${sufijo}.webp`;
  await Promise.all([
    escribir(path.join(RAIZ, carpeta, `${nombre}.webp`), principal.data),
    escribir(path.join(RAIZ, carpeta, `${nombre}_m.webp`), mediana),
    escribir(path.join(RAIZ, carpeta, `${nombre}_t.webp`), miniatura),
  ]);

  return Archivo.create({
    propietario, categoria, nombreOriginal: nombreOriginal ? String(nombreOriginal).slice(0, 255) : null,
    mime: 'image/webp', extension: 'webp',
    bytes: principal.data.length, bytesOptimizado: principal.data.length, optimizado: true,
    ancho: principal.info.width, alto: principal.info.height, hash,
    rutaOriginal: rel(''), rutaOptimizada: rel(''), rutaMediana: rel('_m'), rutaMiniatura: rel('_t'),
    urlPublica: `/${rel('_m')}`, creadoPor: propietario,
  });
}

const baseUrl = (req) => (process.env.PUBLIC_URL ? process.env.PUBLIC_URL.replace(/\/$/, '') : `${req.protocol}://${req.get('host')}`);

// { 'ARC-000001': { url, miniatura } } en UNA sola consulta (para listados). url = tamaño mediano (800 px).
async function mapaUrls(req, codigos) {
  const lista = [...new Set((codigos || []).filter(Boolean))];
  if (!lista.length) return {};
  const filas = await Archivo.findAll({ where: { id: lista }, attributes: ['id', 'rutaMediana', 'rutaMiniatura'] });
  const base = baseUrl(req);
  return Object.fromEntries(filas.map((f) => [f.id, { url: `${base}/${f.rutaMediana}`, miniatura: `${base}/${f.rutaMiniatura}` }]));
}

module.exports = { guardarBase64, mapaUrls };
