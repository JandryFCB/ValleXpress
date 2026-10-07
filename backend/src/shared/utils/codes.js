const crypto = require('crypto');

// Código numérico de 6 dígitos criptográficamente seguro (reemplaza Math.random)
const generarCodigo6 = () => String(crypto.randomInt(100000, 1000000));

module.exports = { generarCodigo6 };
