const admin = require('firebase-admin');

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

    const message = {
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
  sendVerificationCodeNotification,
  sendWelcomeNotification
};
