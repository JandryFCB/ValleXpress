const admin = require('firebase-admin');

// Arma el mensaje de FCM (los valores de "data" deben ser texto)
function armarMensaje(fcmToken, title, body, data = {}) {
  return {
    notification: {
      title,
      body
    },
    data: {
      ...data,
      click_action: 'FLUTTER_NOTIFICATION_CLICK'
    },
    token: fcmToken,
    android: {
      priority: 'high',
      notification: {
        channelId: 'verification_channel',
        priority: 'high',
        sound: 'default',
        vibrateTimings: ['0s', '0.5s', '0.5s']
      }
    }
  };
}

// Igual que sendPushNotification pero DICE qué pasó: { ok } | { ok:false, omitido } | { ok:false, invalido, code }.
// "invalido" = el token ya no existe (app desinstalada...): quien llama debe desactivarlo.
async function enviarPush(fcmToken, title, body, data = {}) {
  if (!admin.apps.length) return { ok: false, omitido: true };
  try {
    await admin.messaging().send(armarMensaje(fcmToken, title, body, data));
    return { ok: true };
  } catch (error) {
    const invalido = ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code);
    return { ok: false, invalido, code: error.code, error: error.message };
  }
}

/**
 * Enviar notificación push a un dispositivo específico
 * @param {string} fcmToken - Token del dispositivo
 * @param {string} title - Título de la notificación
 * @param {string} body - Cuerpo de la notificación
 * @param {object} data - Datos adicionales (opcional)
 */
async function sendPushNotification(fcmToken, title, body, data = {}) {
  try {
    // Verificar que Firebase Admin esté inicializado
    if (!admin.apps.length) {
      console.log('⚠️ Firebase Admin no inicializado, saltando notificación push');
      return null;
    }

    const message = armarMensaje(fcmToken, title, body, data);

    const response = await admin.messaging().send(message);
    console.log('✅ Notificación push enviada:', response);
    return response;
  } catch (error) {
    console.error('❌ Error enviando notificación push:', error.message);
    // No lanzar error para no interrumpir el flujo principal
    return null;
  }
}

/**
 * Enviar notificación de verificación de email
 * @param {string} fcmToken - Token del dispositivo
 * @param {string} code - Código de verificación (opcional, para mostrar en notificación)
 */
async function sendVerificationCodeNotification(fcmToken, code = null) {
  const title = '🔐 Código de Verificación';
  const body = code 
    ? `Tu código es: ${code}. Válido por 15 minutos.`
    : 'Revisa tu email, te hemos enviado un código de verificación.';
  
  return await sendPushNotification(fcmToken, title, body, {
    type: 'email_verification',
    code: code || ''
  });
}

/**
 * Enviar notificación de bienvenida después del registro
 * @param {string} fcmToken - Token del dispositivo
 * @param {string} nombre - Nombre del usuario
 */
async function sendWelcomeNotification(fcmToken, nombre) {
  return await sendPushNotification(
    fcmToken,
    '🎉 ¡Bienvenido a ValleXpress!',
    `Hola ${nombre}, tu cuenta ha sido creada exitosamente.`,
    {
      type: 'welcome',
      screen: 'home'
    }
  );
}

module.exports = {
  sendPushNotification,
  enviarPush,
  sendVerificationCodeNotification,
  sendWelcomeNotification
};
