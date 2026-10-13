const jwt = require('jsonwebtoken');
const AppError = require('../errors/AppError');

// Todo lo relacionado con JWT en un solo lugar.
//   * Token de ACCESO: corto (15 min). Va en cada petición. Cuando vence, la app lo renueva con el refresh token
//     (ver sesion.service.js), por eso el usuario no tiene que volver a escribir su clave.
//   * Token de RESET: de un solo uso, para restablecer la clave.

const EXPIRAACCESO = process.env.JWT_EXPIRA || '15m';

let avisado = false;
function secreto() {
  const s = process.env.JWT_SECRET;
  if (!s) throw new Error('JWT_SECRET no está definido en el .env');
  if (s.length < 32 && !avisado) {
    avisado = true;
    console.warn('⚠️  JWT_SECRET es corto/débil (< 32 caracteres). Cámbialo antes de producción: ver ROADMAP_TOP.md');
  }
  return s;
}

// Segundos de vida del token de acceso (la app lo usa para saber cuándo renovarlo)
const segundosAcceso = () => {
  const m = /^(\d+)([smhd])$/.exec(EXPIRAACCESO);
  if (!m) return Number(EXPIRAACCESO) || 900;
  return Number(m[1]) * { s: 1, m: 60, h: 3600, d: 86400 }[m[2]];
};

// El payload conserva "tipoUsuario" en texto porque lo usan los sockets. No lleva cédula ni otros datos personales.
function crear(usuario) {
  return jwt.sign(
    { id: usuario.id, email: usuario.email, tipoUsuario: usuario.tipoUsuario },
    secreto(),
    { expiresIn: EXPIRAACCESO },
  );
}

function verificar(token) {
  return jwt.verify(token, secreto());          // lanza JsonWebTokenError / TokenExpiredError (errorHandler las traduce)
}

// Token de un solo uso para restablecer la clave: lleva la fecha del último cambio de clave ("cc");
// cuando la clave cambia, ese token deja de servir aunque no haya expirado.
function crearReset(usuario) {
  return jwt.sign(
    { email: usuario.email, userId: usuario.id, purpose: 'reset', cc: usuario.claveCambiadaEn ? new Date(usuario.claveCambiadaEn).getTime() : 0 },
    secreto(),
    { expiresIn: '10m' },
  );
}

function verificarReset(token) {
  let payload;
  try {
    payload = jwt.verify(token, secreto());
  } catch {
    throw AppError.unauthorized('Token inválido o expirado', 'TOKENRESETINVALIDO');
  }
  if (!payload || payload.purpose !== 'reset' || !payload.email) {
    throw AppError.unauthorized('Token inválido', 'TOKENRESETINVALIDO');
  }
  return payload;
}

module.exports = { crear, verificar, crearReset, verificarReset, segundosAcceso };
