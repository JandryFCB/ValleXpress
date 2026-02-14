const jwt = require('jsonwebtoken');
const Usuario = require('../models/Usuario');
const Vendedor = require('../models/Vendedor');
const Repartidor = require('../models/Repartidor');
const PasswordResetCode = require('../models/PasswordResetCode');
const EmailVerificationCode = require('../models/EmailVerificationCode');

const { validationResult } = require('express-validator');
const bcrypt = require('bcryptjs');
const { sequelize } = require('../config/database');

// ✅ Validar formato de email
function validarEmail(email) {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return regex.test(email);
}

// ✅ Validar cédula ecuatoriana (algoritmo completo módulo 10)
function validarCedula(cedula) {
  // Verificar que tenga 10 dígitos
  if (!cedula || String(cedula).length !== 10) return false;
  if (!/^\d{10}$/.test(String(cedula))) return false;
  
  const digitos = cedula.split('').map(Number);
  
  // Los dos primeros dígitos deben ser código de provincia (01-24)
  const provincia = digitos[0] * 10 + digitos[1];
  if (provincia < 1 || provincia > 24) return false;
  
  // Algoritmo de validación módulo 10
  let suma = 0;
  for (let i = 0; i < 9; i++) {
    let mult = digitos[i] * (i % 2 === 0 ? 2 : 1);
    suma += mult > 9 ? mult - 9 : mult;
  }
  
  const verificador = (10 - (suma % 10)) % 10;
  return verificador === digitos[9];
}

// ✅ Validar teléfono ecuatoriano (10 dígitos, empieza con 09)
function validarTelefono(telefono) {
  if (!telefono) return false;
  // Limpiar espacios y guiones
  const limpio = String(telefono).replace(/[\s\-]/g, '');
  // Debe tener 10 dígitos y empezar con 09
  return /^\d{10}$/.test(limpio) && limpio.startsWith('09');
}

// ✅ Validar placa de vehículo (Ecuador: AB1234 o ABC-123)
function validarPlaca(placa) {
  if (!placa) return false;
  // Limpiar espacios y guiones, convertir a mayúsculas
  const limpio = placa.trim().toUpperCase().replace(/[\s\-]/g, '');
  
  // Formato antiguo: 2 letras + 4 números (AB1234)
  const formatoAntiguo = /^[A-Z]{2}\d{4}$/;
  // Formato nuevo: 3 letras + 3 números (ABC123)
  const formatoNuevo = /^[A-Z]{3}\d{3}$/;
  
  return formatoAntiguo.test(limpio) || formatoNuevo.test(limpio);
}

async function register(req, res) {

  const transaction = await sequelize.transaction();
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      await transaction.rollback();
      return res.status(400).json({ errors: errors.array() });
    }

    const {
      nombre,
      apellido,
      email,
      telefono,
      password,
      cedula,
      tipoUsuario,
      nombreNegocio,
      descripcionNegocio,
      categoriaNegocio,
      vehiculo,
      placa,
      licencia
    } = req.body;

    if (!validarEmail(email)) {
      await transaction.rollback();
      return res.status(400).json({ error: 'Formato de email inválido' });
    }
    if (!validarCedula(cedula)) {
      await transaction.rollback();
      return res.status(400).json({ error: 'La cédula debe tener 10 dígitos' });
    }
    if (!validarTelefono(telefono)) {
      await transaction.rollback();
      return res.status(400).json({ error: 'El teléfono debe tener 10 dígitos y empezar con 09 (ej: 0991234567)' });
    }
    if (!password || password.length < 6) {
      await transaction.rollback();
      return res.status(400).json({ error: 'La contraseña debe tener al menos 6 caracteres' });
    }


    const usuarioExistentePorEmail = await Usuario.findOne({ where: { email }, transaction });
    if (usuarioExistentePorEmail) {
      await transaction.rollback();
      return res.status(409).json({ error: 'El email ya está registrado' });
    }

    const usuarioExistentePorCedula = await Usuario.findOne({ where: { cedula }, transaction });
    if (usuarioExistentePorCedula) {
      await transaction.rollback();
      return res.status(409).json({ error: 'La cédula ya está registrada' });
    }

    const usuarioExistentePorTelefono = await Usuario.findOne({ where: { telefono }, transaction });
    if (usuarioExistentePorTelefono) {
      await transaction.rollback();
      return res.status(409).json({ error: 'El teléfono ya está registrado' });
    }


    const tipoUsuarioFinal = tipoUsuario || 'cliente';

    const nuevoUsuario = await Usuario.create({
      nombre,
      apellido,
      email,
      telefono,
      cedula,
      passwordHash: password,
      tipoUsuario: tipoUsuarioFinal,
      activo: true,
      verificado: false,
    }, { transaction });

    // Si es vendedor, crear registro en tabla vendedores
    if (tipoUsuarioFinal === 'vendedor') {
      await Vendedor.create({
        usuarioId: nuevoUsuario.id,
        nombreNegocio: nombreNegocio || `${nombre}'s Business`,
        descripcion: descripcionNegocio || 'Cuéntanos sobre tu negocio',
        categoria: categoriaNegocio || 'Otro',
        calificacionPromedio: 0.00,
        totalCalificaciones: 0,
      }, { transaction });
      console.log('✅ Vendedor creado para:', email);
    }

    // Si es repartidor, validar campos adicionales y crear registro
    if (tipoUsuarioFinal === 'repartidor') {
      // Validar vehículo
      if (!vehiculo || vehiculo.trim().length < 2) {
        await transaction.rollback();
        return res.status(400).json({ error: 'El tipo de vehículo es requerido (mínimo 2 caracteres)' });
      }
      
      // Validar placa
      if (!validarPlaca(placa)) {
        await transaction.rollback();
        return res.status(400).json({ 
          error: 'Placa inválida. Formatos válidos: AB1234, ABC-123, AB-1234 (2-3 letras + 3-4 números)' 
        });
      }
      
      // Normalizar placa a mayúsculas sin guiones
      const placaNormalizada = placa.trim().toUpperCase().replace(/[\s\-]/g, '');
      
      // Verificar que la placa no esté registrada por otro repartidor
      const placaExistente = await Repartidor.findOne({ 
        where: { placa: placaNormalizada },
        transaction 
      });
      if (placaExistente) {
        await transaction.rollback();
        return res.status(409).json({ error: 'Esta placa ya está registrada por otro repartidor' });
      }
      
      // Validar licencia
      if (!licencia || licencia.trim().length < 5) {
        await transaction.rollback();
        return res.status(400).json({ error: 'El número de licencia es requerido (mínimo 5 caracteres)' });
      }

      await Repartidor.create({
        usuarioId: nuevoUsuario.id,
        vehiculo: vehiculo.trim(),
        placa: placaNormalizada,
        licencia: licencia.trim().toUpperCase(),
        calificacionPromedio: 0.00,
        totalCalificaciones: 0,
        disponible: false,
        latitud: null,
        longitud: null,
        pedidosCompletados: 0,
        cedula: nuevoUsuario.cedula,
      }, { transaction });
      console.log('✅ Repartidor creado para:', email);
    }


    await transaction.commit();

    const token = jwt.sign(
      { id: nuevoUsuario.id, email: nuevoUsuario.email, tipoUsuario: nuevoUsuario.tipoUsuario, cedula: nuevoUsuario.cedula },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    return res.status(201).json({
      message: 'Usuario registrado exitosamente',
      usuario: {
        id: nuevoUsuario.id,
        nombre: nuevoUsuario.nombre,
        apellido: nuevoUsuario.apellido,
        email: nuevoUsuario.email,
        telefono: nuevoUsuario.telefono,
        cedula: nuevoUsuario.cedula,
        tipoUsuario: nuevoUsuario.tipoUsuario,
        activo: nuevoUsuario.activo,
        verificado: nuevoUsuario.verificado,
      },
      token,
    });
  } catch (error) {
    await transaction.rollback();
    console.error('Error en registro:', error);
    return res.status(500).json({ error: 'Error al registrar usuario' });
  }
}

async function login(req, res) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { email, password } = req.body;

    if (!validarEmail(email)) return res.status(400).json({ error: 'Formato de email inválido' });

    const usuario = await Usuario.findOne({ where: { email } });
    if (!usuario) return res.status(401).json({ error: 'Credenciales inválidas' });

    if (!usuario.activo) return res.status(403).json({ error: 'Cuenta desactivada' });

    const passwordValido = await usuario.verificarPassword(password);
    if (!passwordValido) return res.status(401).json({ error: 'Credenciales inválidas' });

    await usuario.update({ ultimaConexion: new Date() });

    const token = jwt.sign(
      { id: usuario.id, email: usuario.email, tipoUsuario: usuario.tipoUsuario, cedula: usuario.cedula },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    // Si el usuario es vendedor o repartidor y no tiene el perfil correspondiente, crearlo por defecto
    try {
      if (usuario.tipoUsuario === 'vendedor') {
        const vendedorExistente = await Vendedor.findOne({ where: { usuarioId: usuario.id } });
        if (!vendedorExistente) {
          await Vendedor.create({
            usuarioId: usuario.id,
            nombreNegocio: `${usuario.nombre}'s Business`,
            descripcion: 'Cuéntanos sobre tu negocio',
            categoria: 'Otro',
            calificacionPromedio: 0.00,
            totalCalificaciones: 0,
          });
          console.log('✅ Vendedor creado automáticamente en login para:', usuario.email);
        }
      }

      if (usuario.tipoUsuario === 'repartidor') {
        const repartidorExistente = await Repartidor.findOne({ where: { usuarioId: usuario.id } });
        if (!repartidorExistente) {
          await Repartidor.create({
            usuarioId: usuario.id,
            vehiculo: 'No especificado',
            placa: 'No especificada',
            licencia: 'No especificada',
            calificacionPromedio: 0.00,
            totalCalificaciones: 0,
            disponible: false,
            pedidosCompletados: 0,
          });
          console.log('✅ Repartidor creado automáticamente en login para:', usuario.email);
        }
      }
    } catch (creationError) {
      console.error('Error al crear perfil automático en login:', creationError);
    }

    return res.json({
      message: 'Inicio de sesión exitoso',
      usuario: {
        id: usuario.id,
        nombre: usuario.nombre,
        apellido: usuario.apellido,
        email: usuario.email,
        telefono: usuario.telefono,
        cedula: usuario.cedula,
        tipoUsuario: usuario.tipoUsuario,
        activo: usuario.activo,
        verificado: usuario.verificado,
      },
      token,
    });
  } catch (error) {
    console.error('Error en login:', error);
    return res.status(500).json({ error: 'Error al iniciar sesión' });
  }
}

async function getProfile(req, res) {
  try {
    const usuario = await Usuario.findByPk(req.usuario.id, {
      attributes: { exclude: ['passwordHash'] },
    });
    if (!usuario) return res.status(404).json({ error: 'Usuario no encontrado' });
    return res.json({ usuario });
  } catch (error) {
    console.error('Error al obtener perfil:', error);
    return res.status(500).json({ error: 'Error al obtener perfil' });
  }
}

async function updateProfile(req, res) {
  try {
    const { nombre, apellido, telefono, fotoPerfil } = req.body;
    const usuario = await Usuario.findByPk(req.usuario.id);
    if (!usuario) return res.status(404).json({ error: 'Usuario no encontrado' });

    await usuario.update({
      ...(nombre && { nombre }),
      ...(apellido && { apellido }),
      ...(telefono && { telefono }),
      ...(fotoPerfil && { fotoPerfil }),
    });

    return res.json({ message: 'Perfil actualizado exitosamente', usuario });
  } catch (error) {
    console.error('Error al actualizar perfil:', error);
    return res.status(500).json({ error: 'Error al actualizar perfil' });
  }
}

async function changePassword(req, res) {
  try {
    const { passwordActual, passwordNueva } = req.body;
    const usuario = await Usuario.findByPk(req.usuario.id);

    const passwordValido = await usuario.verificarPassword(passwordActual);
    if (!passwordValido) return res.status(401).json({ error: 'Contraseña actual incorrecta' });

    await usuario.update({ passwordHash: passwordNueva });
    return res.json({ message: 'Contraseña actualizada exitosamente' });
  } catch (error) {
    console.error('Error al cambiar contraseña:', error);
    return res.status(500).json({ error: 'Error al cambiar contraseña' });
  }
}

// 1) Solicitar código
async function forgotPassword(req, res) {
  try {
    const email = (req.body.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ error: 'Email requerido' });
    if (!validarEmail(email)) return res.status(400).json({ error: 'Formato de email inválido' });

    const user = await Usuario.findOne({ where: { email } });

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const codeHash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    await PasswordResetCode.update({ usedAt: new Date() }, { where: { email, usedAt: null } });

    await PasswordResetCode.create({
      email,
      userId: user ? user.id : null,
      codeHash,
      expiresAt,
      attempts: 0,
      usedAt: null,
    });

    // Enviar correo real si está configurado, si falla no interrumpe respuesta al cliente
    try {
      const mailer = require('../services/mailer.service');
      await mailer.sendPasswordResetCode(email, code);
    } catch (mailErr) {
      console.error('Error enviando email reset:', mailErr);
      // Fallback: log el código en consola para entornos de desarrollo
      console.log(`[RESET] Código para ${email}: ${code}`);
    }

    return res.json({ message: 'Si el correo existe, te enviamos un código de verificación.' });
  } catch (e) {
    console.error('Error forgotPassword:', e);
    return res.status(500).json({ error: 'Error al solicitar recuperación' });
  }
}

// 2) Verificar código
async function verifyResetCode(req, res) {
  try {
    const email = (req.body.email || '').trim().toLowerCase();
    const code = (req.body.code || '').trim();

    if (!email || !code) return res.status(400).json({ error: 'Email y código son requeridos' });
    if (!validarEmail(email)) return res.status(400).json({ error: 'Formato de email inválido' });
    if (code.length !== 6) return res.status(400).json({ error: 'El código debe tener 6 dígitos' });

    const record = await PasswordResetCode.findOne({
      where: { email, usedAt: null },
      order: [['createdAt', 'DESC']],
    });

    if (!record || record.expiresAt < new Date()) return res.status(400).json({ error: 'Código inválido o expirado' });
    if (record.attempts >= 5) return res.status(400).json({ error: 'Demasiados intentos. Solicita un nuevo código.' });

    const ok = await bcrypt.compare(code, record.codeHash);
    if (!ok) {
      await record.update({ attempts: record.attempts + 1 });
      return res.status(400).json({ error: 'Código inválido o expirado' });
    }

    await record.update({ usedAt: new Date() });

    const resetToken = jwt.sign(
      { email, userId: record.userId, purpose: 'reset' },
      process.env.JWT_SECRET,
      { expiresIn: '10m' }
    );

    return res.json({ resetToken });
  } catch (e) {
    console.error('Error verifyResetCode:', e);
    return res.status(500).json({ error: 'Error al verificar código' });
  }
}

// 3) Reset final
async function resetPassword(req, res) {
  try {
    const resetToken = (req.body.resetToken || '').trim();
    const newPassword = (req.body.newPassword || '').trim();

    if (!resetToken || !newPassword) return res.status(400).json({ error: 'Token y nueva contraseña son requeridos' });
    if (newPassword.length < 6) return res.status(400).json({ error: 'La contraseña debe tener al menos 6 caracteres' });

    let payload;
    try {
      payload = jwt.verify(resetToken, process.env.JWT_SECRET);
    } catch {
      return res.status(401).json({ error: 'Token inválido o expirado' });
    }

    if (!payload || payload.purpose !== 'reset' || !payload.email) return res.status(401).json({ error: 'Token inválido' });

    const user = await Usuario.findOne({ where: { email: payload.email } });
    if (!user) return res.status(401).json({ error: 'Token inválido' });

    await user.update({ passwordHash: newPassword });

    return res.json({ message: 'Contraseña actualizada correctamente' });
  } catch (e) {
    console.error('Error resetPassword:', e);
    return res.status(500).json({ error: 'Error al resetear contraseña' });
  }
}

// 4) Enviar código de verificación de email
async function sendEmailVerification(req, res) {
  try {
    const { email, nombre, fcmToken } = req.body;
    
    if (!email || !validarEmail(email)) {
      return res.status(400).json({ error: 'Email inválido' });
    }

    // ⏱️ Verificar tiempo mínimo entre reenvíos (60 segundos)
    const ultimoCodigo = await EmailVerificationCode.findOne({
      where: { email, usedAt: null },
      order: [['createdAt', 'DESC']],
    });

    if (ultimoCodigo) {
      const segundosDesdeUltimo = (new Date() - new Date(ultimoCodigo.createdAt)) / 1000;
      if (segundosDesdeUltimo < 60) {
        const segundosRestantes = Math.ceil(60 - segundosDesdeUltimo);
        return res.status(429).json({ 
          error: `Espera ${segundosRestantes} segundos antes de solicitar un nuevo código`,
          retryAfter: segundosRestantes
        });
      }
    }

    // Generar código de 6 dígitos
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const codeHash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutos

    // Invalidar códigos anteriores
    await EmailVerificationCode.update(
      { usedAt: new Date() },
      { where: { email, usedAt: null } }
    );

    // Crear nuevo código con FCM token
    await EmailVerificationCode.create({
      email,
      codeHash,
      expiresAt,
      attempts: 0,
      usedAt: null,
      fcmToken: fcmToken || null,
    });

    // Enviar email
    try {
      const mailer = require('../services/mailer.service');
      await mailer.sendEmailVerificationCode(email, code, nombre || 'Usuario');
    } catch (mailErr) {
      console.error('Error enviando email de verificación:', mailErr);
      console.log(`[VERIFY] Código para ${email}: ${code}`);
    }

    // Enviar notificación push si hay FCM token
    if (fcmToken) {
      try {
        const fcmService = require('../services/fcm.service');
        await fcmService.sendVerificationCodeNotification(fcmToken, code);
      } catch (fcmErr) {
        console.error('Error enviando notificación push:', fcmErr);
        // No interrumpir el flujo si falla la notificación push
      }
    }

    return res.json({ message: 'Código de verificación enviado' });
  } catch (e) {
    console.error('Error sendEmailVerification:', e);
    return res.status(500).json({ error: 'Error al enviar código' });
  }
}



// 5) Verificar código de email
async function verifyEmailCode(req, res) {
  try {
    const { email, code } = req.body;

    if (!email || !code) {
      return res.status(400).json({ error: 'Email y código son requeridos' });
    }
    if (!validarEmail(email)) {
      return res.status(400).json({ error: 'Email inválido' });
    }
    if (code.length !== 6) {
      return res.status(400).json({ error: 'El código debe tener 6 dígitos' });
    }

    const record = await EmailVerificationCode.findOne({
      where: { email, usedAt: null },
      order: [['createdAt', 'DESC']],
    });

    if (!record || record.expiresAt < new Date()) {
      return res.status(400).json({ error: 'Código expirado' });
    }
    if (record.attempts >= 5) {
      return res.status(400).json({ error: 'Demasiados intentos' });
    }

    const ok = await bcrypt.compare(code, record.codeHash);
    if (!ok) {
      await record.update({ attempts: record.attempts + 1 });
      return res.status(400).json({ error: 'Código incorrecto' });
    }

    await record.update({ usedAt: new Date() });

    return res.json({ 
      message: 'Email verificado correctamente',
      verified: true 
    });
  } catch (e) {
    console.error('Error verifyEmailCode:', e);
    return res.status(500).json({ error: 'Error al verificar código' });
  }
}

// ✅ Verificar si cédula ya existe (validación en tiempo real)
async function checkCedula(req, res) {
  try {
    const { cedula } = req.params;
    
    if (!cedula || !/^\d{10}$/.test(cedula)) {
      return res.status(400).json({ error: 'Cédula inválida' });
    }

    const existe = await Usuario.findOne({ where: { cedula } });
    
    return res.json({ 
      exists: !!existe,
      message: existe ? 'Esta cédula ya está registrada' : 'Cédula disponible'
    });
  } catch (e) {
    console.error('Error checkCedula:', e);
    return res.status(500).json({ error: 'Error al verificar cédula' });
  }
}

// ✅ Verificar si email ya existe (validación en tiempo real)
async function checkEmail(req, res) {
  try {
    const { email } = req.params;
    
    if (!email || !validarEmail(email)) {
      return res.status(400).json({ error: 'Email inválido' });
    }

    const existe = await Usuario.findOne({ 
      where: { email: email.toLowerCase().trim() } 
    });
    
    return res.json({ 
      exists: !!existe,
      message: existe ? 'Este email ya está registrado' : 'Email disponible'
    });
  } catch (e) {
    console.error('Error checkEmail:', e);
    return res.status(500).json({ error: 'Error al verificar email' });
  }
}

// ✅ Verificar si placa ya existe (validación en tiempo real para repartidores)
async function checkPlaca(req, res) {
  try {
    const { placa } = req.params;
    
    if (!placa || !validarPlaca(placa)) {
      return res.status(400).json({ error: 'Placa inválida' });
    }

    // Normalizar placa
    const placaNormalizada = placa.trim().toUpperCase().replace(/[\s\-]/g, '');

    const existe = await Repartidor.findOne({ 
      where: { placa: placaNormalizada } 
    });
    
    return res.json({ 
      exists: !!existe,
      message: existe ? 'Esta placa ya está registrada' : 'Placa disponible'
    });
  } catch (e) {
    console.error('Error checkPlaca:', e);
    return res.status(500).json({ error: 'Error al verificar placa' });
  }
}

module.exports = {
  register,
  login,
  getProfile,
  updateProfile,
  changePassword,
  forgotPassword,
  verifyResetCode,
  resetPassword,
  sendEmailVerification,
  verifyEmailCode,
  checkCedula,
  checkEmail,
  checkPlaca,
};
