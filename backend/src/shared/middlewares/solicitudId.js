const crypto = require('crypto');

// Asigna un identificador a cada petición (req.solicitudId). Sirve para unir en LOGMENSAJES y LOGERRORES
// todo lo ocurrido en una misma petición. Se devuelve en la cabecera X-Request-Id; si el cliente ya manda
// uno con formato válido, se respeta.
module.exports = (req, res, next) => {
  const entrante = req.headers['x-request-id'];
  req.solicitudId = typeof entrante === 'string' && /^[\w-]{8,64}$/.test(entrante) ? entrante : crypto.randomUUID();
  res.setHeader('X-Request-Id', req.solicitudId);
  next();
};
