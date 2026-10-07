const { normalizarPlaca, normalizarTelefono } = require('./normalizers');

const validarEmail = (email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || ''));

// Cédula ecuatoriana: 10 dígitos, provincia 01-24 y dígito verificador módulo 10
function validarCedula(cedula) {
  const c = String(cedula || '');
  if (!/^\d{10}$/.test(c)) return false;
  const d = c.split('').map(Number);
  const provincia = d[0] * 10 + d[1];
  if (provincia < 1 || provincia > 24) return false;
  let suma = 0;
  for (let i = 0; i < 9; i++) {
    const mult = d[i] * (i % 2 === 0 ? 2 : 1);
    suma += mult > 9 ? mult - 9 : mult;
  }
  return (10 - (suma % 10)) % 10 === d[9];
}

// Teléfono ecuatoriano móvil: 10 dígitos que empiezan con 09
const validarTelefono = (tel) => /^09\d{8}$/.test(normalizarTelefono(tel));

// Placa: AB1234 (antigua) o ABC123 (nueva)
const validarPlaca = (placa) => /^([A-Z]{2}\d{4}|[A-Z]{3}\d{3})$/.test(normalizarPlaca(placa));

// Usuario para iniciar sesión (jcayapa): 3 a 30 letras minúsculas o números, sin símbolos
const validarUsuario = (usuario) => /^[a-z0-9]{3,30}$/.test(String(usuario || ''));

// Lo que se escribe en el campo de login: un email o un usuario
const validarIdentificador = (valor) => {
  const v = String(valor || '');
  return v.includes('@') ? validarEmail(v) : validarUsuario(v);
};

module.exports = { validarEmail, validarCedula, validarTelefono, validarPlaca, validarUsuario, validarIdentificador };
