const SibApiV3Sdk = require('sib-api-v3-sdk');

const defaultClient = SibApiV3Sdk.ApiClient.instance;
const apiKey = defaultClient.authentications['api-key'];
apiKey.apiKey = process.env.BREVO_API_KEY;

const apiInstance = new SibApiV3Sdk.TransactionalEmailsApi();

// Configuración anti-spam
const SENDER_NAME = 'ValleXpress';
const SENDER_EMAIL = process.env.SMTP_FROM || 'soporte@vallexpress.com';
const REPLY_TO_EMAIL = process.env.REPLY_TO_EMAIL || 'soporte@vallexpress.com';

// Headers anti-spam
function getAntiSpamHeaders() {
  return {
    'X-Mailer': 'ValleXpress-Email-Service/1.0',
    'X-Priority': '3', // Normal priority
    'Precedence': 'bulk',
    'Auto-Submitted': 'auto-generated',
    'X-Auto-Response-Suppress': 'OOF, AutoReply'
  };
}

// Enviar email de verificación
async function sendEmailVerificationCode(toEmail, code, nombre) {
  const sendSmtpEmail = new SibApiV3Sdk.SendSmtpEmail();
  
  // Headers anti-spam
  sendSmtpEmail.headers = getAntiSpamHeaders();
  
  // Reply-To configurado
  sendSmtpEmail.replyTo = {
    email: REPLY_TO_EMAIL,
    name: SENDER_NAME
  };
  
  sendSmtpEmail.subject = 'Tu código de verificación - ValleXpress';
  sendSmtpEmail.htmlContent = `
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <title>Código de Verificación - ValleXpress</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 20px 0;">
        <table role="presentation" style="width: 600px; border-collapse: collapse; background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <tr>
            <td style="padding: 40px 30px; text-align: center; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 8px 8px 0 0;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: 600;">ValleXpress</h1>
            </td>
          </tr>
          <tr>
            <td style="padding: 40px 30px;">
              <h2 style="color: #333333; margin: 0 0 20px 0; font-size: 24px;">Hola ${nombre},</h2>
              <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 30px 0;">
                Gracias por registrarte en ValleXpress. Para completar tu registro, usa el siguiente código de verificación:
              </p>
              
              <table role="presentation" style="width: 100%; margin: 30px 0;">
                <tr>
                  <td align="center">
                    <div style="background-color: #f8f9fa; border: 2px dashed #667eea; border-radius: 8px; padding: 30px; display: inline-block;">
                      <span style="font-size: 36px; font-weight: bold; letter-spacing: 12px; color: #333333; font-family: 'Courier New', monospace;">
                        ${code}
                      </span>
                    </div>
                  </td>
                </tr>
              </table>
              
              <p style="color: #999999; font-size: 14px; text-align: center; margin: 20px 0;">
                ⏱️ Este código expira en <strong>15 minutos</strong>
              </p>
              
              <hr style="border: none; border-top: 1px solid #eeeeee; margin: 30px 0;">
              
              <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 0;">
                Si no solicitaste este código, puedes ignorar este mensaje de forma segura. Tu cuenta no será creada.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding: 30px; text-align: center; background-color: #f8f9fa; border-radius: 0 0 8px 8px;">
              <p style="color: #999999; font-size: 12px; margin: 0 0 10px 0;">
                © 2024 ValleXpress. Todos los derechos reservados.
              </p>
              <p style="color: #999999; font-size: 12px; margin: 0;">
                Este es un email automático, por favor no respondas a este mensaje.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `;
  
  sendSmtpEmail.textContent = `ValleXpress - Código de Verificación

Hola ${nombre},

Gracias por registrarte en ValleXpress. Tu código de verificación es:

${code}

Este código expira en 15 minutos.

Si no solicitaste este código, ignora este mensaje.

© 2024 ValleXpress
Soporte: ${REPLY_TO_EMAIL}`;
  
  sendSmtpEmail.sender = {
    name: SENDER_NAME,
    email: SENDER_EMAIL
  };
  sendSmtpEmail.to = [{ email: toEmail }];
  sendSmtpEmail.tags = ['verification', 'vallexpress', 'transactional'];

  try {
    const data = await apiInstance.sendTransacEmail(sendSmtpEmail);
    console.log('✅ Email de verificación enviado via Brevo:', data.messageId);
    return data;
  } catch (error) {
    console.error('❌ Error enviando email Brevo:', error.message);
    throw error;
  }
}


// Enviar código de reset de contraseña
async function sendPasswordResetCode(toEmail, code) {
  const sendSmtpEmail = new SibApiV3Sdk.SendSmtpEmail();
  
  // Headers anti-spam
  sendSmtpEmail.headers = getAntiSpamHeaders();
  
  // Reply-To configurado
  sendSmtpEmail.replyTo = {
    email: REPLY_TO_EMAIL,
    name: SENDER_NAME
  };
  
  sendSmtpEmail.subject = 'Recuperación de contraseña - ValleXpress';
  sendSmtpEmail.htmlContent = `
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Recuperación de Contraseña - ValleXpress</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 20px 0;">
        <table role="presentation" style="width: 600px; border-collapse: collapse; background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <tr>
            <td style="padding: 40px 30px; text-align: center; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 8px 8px 0 0;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: 600;">ValleXpress</h1>
            </td>
          </tr>
          <tr>
            <td style="padding: 40px 30px;">
              <h2 style="color: #333333; margin: 0 0 20px 0; font-size: 24px;">Recuperación de contraseña</h2>
              <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 30px 0;">
                Has solicitado restablecer tu contraseña. Usa el siguiente código:
              </p>
              
              <table role="presentation" style="width: 100%; margin: 30px 0;">
                <tr>
                  <td align="center">
                    <div style="background-color: #f8f9fa; border: 2px dashed #667eea; border-radius: 8px; padding: 30px; display: inline-block;">
                      <span style="font-size: 36px; font-weight: bold; letter-spacing: 12px; color: #333333; font-family: 'Courier New', monospace;">
                        ${code}
                      </span>
                    </div>
                  </td>
                </tr>
              </table>
              
              <p style="color: #999999; font-size: 14px; text-align: center; margin: 20px 0;">
                ⏱️ Este código expira en <strong>10 minutos</strong>
              </p>
              
              <hr style="border: none; border-top: 1px solid #eeeeee; margin: 30px 0;">
              
              <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 0;">
                Si no solicitaste este código, ignora este mensaje. Tu contraseña no será cambiada.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding: 30px; text-align: center; background-color: #f8f9fa; border-radius: 0 0 8px 8px;">
              <p style="color: #999999; font-size: 12px; margin: 0 0 10px 0;">
                © 2024 ValleXpress. Todos los derechos reservados.
              </p>
              <p style="color: #999999; font-size: 12px; margin: 0;">
                Soporte: ${REPLY_TO_EMAIL}
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `;
  
  sendSmtpEmail.textContent = `ValleXpress - Recuperación de Contraseña

Has solicitado restablecer tu contraseña.

Tu código de recuperación es: ${code}

Este código expira en 10 minutos.

Si no solicitaste este código, ignora este mensaje.

© 2024 ValleXpress
Soporte: ${REPLY_TO_EMAIL}`;
  
  sendSmtpEmail.sender = {
    name: SENDER_NAME,
    email: SENDER_EMAIL
  };
  sendSmtpEmail.to = [{ email: toEmail }];
  sendSmtpEmail.tags = ['password-reset', 'vallexpress', 'transactional'];

  try {
    const data = await apiInstance.sendTransacEmail(sendSmtpEmail);
    console.log('✅ Email de reset enviado via Brevo:', data.messageId);
    return data;
  } catch (error) {
    console.error('❌ Error enviando email Brevo:', error.message);
    throw error;
  }
}


module.exports = {
  sendEmailVerificationCode,
  sendPasswordResetCode
};
