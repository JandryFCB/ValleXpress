const jwt = require('jsonwebtoken');
const AppError = require('../errors/AppError');

// Todo lo relacionado con JWT en un solo lugar (antes jwt.sign estaba repetido en varios controllers).

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

// Token de sesión. El payload conserva "tipoUsuario" en texto porque lo usan los sockets y los módulos aún no migrados.
function crear(usuario) {
  return jwt.sign(
    { id: usuario.id, email: usuario.email, tipoUsuario: usuario.tipoUsuario, cedula: usuario.cedula },
    secreto(),
    { expiresIn: process.env.JWT_EXPIRA || '30d' },
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

module.exports = { crear, verificar, crearReset, verificarReset };
