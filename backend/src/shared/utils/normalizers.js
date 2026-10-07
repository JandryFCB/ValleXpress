const normalizarEmail = (email) => String(email || '').trim().toLowerCase();
const normalizarPlaca = (placa) => String(placa || '').trim().toUpperCase().replace(/[\s-]/g, '');
const normalizarTelefono = (tel) => String(tel || '').replace(/[\s-]/g, '');

const normalizarUsuario = (usuario) => String(usuario || '').trim().toLowerCase();

module.exports = { normalizarEmail, normalizarPlaca, normalizarTelefono, normalizarUsuario };
