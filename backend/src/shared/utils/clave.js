const bcrypt = require('bcryptjs');

const COSTO = 10;

const hashClave = (clave) => bcrypt.hash(String(clave), COSTO);
const compararClave = (clave, hash) => bcrypt.compare(String(clave), String(hash));

// Hash de relleno: se compara contra él cuando el usuario no existe, para que responder
// "credenciales inválidas" tarde lo mismo exista o no la cuenta (evita enumerar usuarios por tiempo).
const HASHRELLENO = bcrypt.hashSync('relleno-para-igualar-tiempos', COSTO);

module.exports = { hashClave, compararClave, HASHRELLENO };
