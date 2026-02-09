const nodemailer = require('nodemailer');

// SendGrid SMTP Configuration for Production
const transporter = nodemailer.createTransport({
  host: 'smtp.sendgrid.net',
  port: 587,
  secure: false, // TLS
  auth: {
    user: 'apikey', // SendGrid uses "apikey" as username
    pass: process.env.SENDGRID_API_KEY || '',
  },
});


async function sendMail({ to, subject, text, html }) {
  const from = process.env.SMTP_FROM || 'soporte@vallexpress.com';
  console.log(`📧 Intentando enviar email desde: ${from} a: ${to}`);
  console.log(`🔑 SMTP_FROM env: ${process.env.SMTP_FROM || 'no definido (usando default)'}`);
  const info = await transporter.sendMail({ from, to, subject, text, html });
  console.log(`✅ Email enviado: ${info.messageId}`);
  return info;
}



async function sendPasswordResetCode(email, code) {
  const subject = '🔐 ValleXpress - Código de recuperación de contraseña';
  
  const text = `ValleXpress - Recuperación de contraseña\n\nTu código de verificación es: ${code}\n\nEste código es válido por 10 minutos.\n\nSi no solicitaste este código, ignora este mensaje.`;
  
  const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Recuperación de contraseña - ValleXpress</title>
    </head>
    <body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
      <table role="presentation" style="width: 100%; border-collapse: collapse;">
        <tr>
          <td align="center" style="padding: 40px 0;">
            <table role="presentation" style="width: 600px; border-collapse: collapse; background-color: #ffffff; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.1);">
              <!-- Header -->
              <tr>
                <td style="padding: 40px 40px 20px 40px; text-align: center; background: linear-gradient(135deg, #0F3A4A 0%, #1a5a6e 100%); border-radius: 16px 16px 0 0;">
                  <h1 style="color: #FDB827; margin: 0; font-size: 28px; font-weight: 800;">ValleXpress</h1>
                  <p style="color: #ffffff; margin: 8px 0 0 0; font-size: 14px;">Recuperación de contraseña</p>
                </td>
              </tr>
              
              <!-- Content -->
              <tr>
                <td style="padding: 40px;">
                  <h2 style="color: #0F3A4A; margin: 0 0 20px 0; font-size: 22px;">Hola,</h2>
                  <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 30px 0;">
                    Recibimos una solicitud para restablecer tu contraseña. Usa el siguiente código de verificación:
                  </p>
                  
                  <!-- Code Box -->
                  <div style="background: linear-gradient(135deg, #FDB827 0%, #ffc947 100%); border-radius: 12px; padding: 30px; text-align: center; margin: 30px 0;">
                    <p style="color: #0F3A4A; font-size: 14px; margin: 0 0 10px 0; font-weight: 600; letter-spacing: 1px;">CÓDIGO DE VERIFICACIÓN</p>
                    <h1 style="color: #0F3A4A; font-size: 48px; margin: 0; font-weight: 900; letter-spacing: 8px; font-family: 'Courier New', monospace;">${code}</h1>
                  </div>
                  
                  <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 30px 0 0 0; text-align: center;">
                    ⏱️ Este código expira en <strong>10 minutos</strong>
                  </p>
                  
                  <div style="border-top: 1px solid #eeeeee; margin: 30px 0; padding-top: 20px;">
                    <p style="color: #999999; font-size: 12px; line-height: 1.6; margin: 0;">
                      Si no solicitaste este código, puedes ignorar este mensaje de forma segura. Tu cuenta está protegida.
                    </p>
                  </div>
                </td>
              </tr>
              
              <!-- Footer -->
              <tr>
                <td style="padding: 20px 40px 40px 40px; text-align: center; background-color: #f9f9f9; border-radius: 0 0 16px 16px;">
                  <p style="color: #999999; font-size: 12px; margin: 0;">
                    © ${new Date().getFullYear()} ValleXpress. Todos los derechos reservados.<br>
                    Yantzaza, Ecuador 🚀
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
  
  return sendMail({ to: email, subject, text, html });
}


module.exports = { sendMail, sendPasswordResetCode };
