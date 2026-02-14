// ✅ Usando Brevo (mejor entregabilidad que SendGrid)
const brevo = require('./brevo.service');

// Re-exportar funciones de Brevo
module.exports = {
  sendEmailVerificationCode: brevo.sendEmailVerificationCode,
  sendPasswordResetCode: brevo.sendPasswordResetCode,
  // Mantener compatibilidad con código antiguo
  sendMail: async ({ to, subject, html, text }) => {
    const SibApiV3Sdk = require('sib-api-v3-sdk');
    const defaultClient = SibApiV3Sdk.ApiClient.instance;
    const apiKey = defaultClient.authentications['api-key'];
    apiKey.apiKey = process.env.BREVO_API_KEY;
    
    const apiInstance = new SibApiV3Sdk.TransactionalEmailsApi();
    
    const sendSmtpEmail = new SibApiV3Sdk.SendSmtpEmail();
    sendSmtpEmail.subject = subject;
    sendSmtpEmail.htmlContent = html;
    sendSmtpEmail.textContent = text;
    sendSmtpEmail.sender = {
      name: 'ValleXpress',
      email: process.env.SMTP_FROM || 'noreply@vallexpress.com'
    };
    sendSmtpEmail.to = [{ email: to }];
    
    return await apiInstance.sendTransacEmail(sendSmtpEmail);
  }
};
