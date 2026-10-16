// Correos de ValleXpress por la API de Brevo (https://api.brevo.com/v3/smtp/email).
//   * BREVO_API_KEY: clave de la API (Brevo → SMTP y API → Claves API).
//   * SMTP_FROM: remitente verificado en Brevo. REPLY_TO_EMAIL: a dónde llegan las respuestas (soporte).
// Todos los correos usan la misma plantilla con los colores de la marca. Si falta la clave, enviar() lanza
// CORREONOCONFIGURADO (quien llama decide qué hacer: el registro, por ejemplo, imprime el código en desarrollo).
const { logMensaje } = require('./log.service');

const MARCA = { verde: '#35B35A', verdeOscuro: '#1F7A3C', amarillo: '#F6B92B', fondo: '#F3F7F4', texto: '#1B2A22', suave: '#5E6E64' };
const remitente = () => process.env.SMTP_FROM;
const soporte = () => process.env.REPLY_TO_EMAIL || process.env.SMTP_FROM || null;
const configurado = () => Boolean(process.env.BREVO_API_KEY && process.env.SMTP_FROM);

const escapar = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// Plantilla: cabecera verde con el nombre, título, párrafos, un bloque destacado opcional (código o datos) y pie
function plantilla({ titulo, saludo, parrafos = [], destacado, notaDestacado, avisoFinal }) {
  const p = (t) => `<p style="margin:0 0 16px;color:${MARCA.suave};font-size:16px;line-height:1.6">${t}</p>`;
  const bloque = destacado
    ? `<div style="margin:24px 0;text-align:center">
         <div style="display:inline-block;background:${MARCA.fondo};border:2px dashed ${MARCA.verde};border-radius:14px;padding:20px 28px">
           ${destacado}
         </div>
         ${notaDestacado ? `<p style="margin:12px 0 0;color:${MARCA.suave};font-size:14px">${notaDestacado}</p>` : ''}
       </div>`
    : '';
  const contacto = soporte() ? `¿Dudas? Escríbenos a <a href="mailto:${escapar(soporte())}" style="color:${MARCA.verdeOscuro}">${escapar(soporte())}</a>` : '';
  return `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapar(titulo)}</title></head>
<body style="margin:0;padding:0;background:${MARCA.fondo};font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
  <table role="presentation" width="100%" style="border-collapse:collapse"><tr><td align="center" style="padding:24px 12px">
    <table role="presentation" width="100%" style="max-width:560px;border-collapse:collapse;background:#ffffff;border-radius:20px;overflow:hidden">
      <tr><td style="background:linear-gradient(135deg,${MARCA.verde},${MARCA.verdeOscuro});padding:28px;text-align:center">
        <div style="font-size:26px;font-weight:800;color:#ffffff;letter-spacing:.5px">Valle<span style="color:${MARCA.amarillo}">Xpress</span></div>
        <div style="color:#E6F4EA;font-size:13px;margin-top:4px">Lo mejor del valle, a tu puerta</div>
      </td></tr>
      <tr><td style="padding:32px 28px 8px">
        <h1 style="margin:0 0 8px;color:${MARCA.texto};font-size:22px">${escapar(titulo)}</h1>
        ${saludo ? `<p style="margin:0 0 16px;color:${MARCA.texto};font-size:16px;font-weight:600">${escapar(saludo)}</p>` : ''}
        ${parrafos.map(p).join('')}
        ${bloque}
        ${avisoFinal ? `<p style="margin:8px 0 24px;padding:12px 14px;background:#FFF7E3;border-radius:12px;color:#7A5A00;font-size:14px;line-height:1.5">${avisoFinal}</p>` : ''}
      </td></tr>
      <tr><td style="padding:20px 28px;background:${MARCA.fondo};text-align:center;color:${MARCA.suave};font-size:12px;line-height:1.6">
        ${contacto}<br>Este es un correo automático de ValleXpress · Yantzaza, Ecuador
      </td></tr>
    </table>
  </td></tr></table>
</body></html>`;
}

const textoPlano = (html) => html.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<br\s*\/?>/g, '\n').replace(/<\/(p|h1|div|tr)>/g, '\n').replace(/<[^>]+>/g, '')
  .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n\n').trim();

// Envía un correo. Lanza un error si no está configurado o si Brevo lo rechaza.
async function enviar({ para, nombre, asunto, html, etiquetas = [] }) {
  if (!configurado()) {
    const e = new Error('El envío de correos no está configurado (BREVO_API_KEY y SMTP_FROM)');
    e.code = 'CORREONOCONFIGURADO';
    throw e;
  }
  const r = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': process.env.BREVO_API_KEY, accept: 'application/json', 'content-type': 'application/json' },
    body: JSON.stringify({
      sender: { name: 'ValleXpress', email: remitente() },
      ...(soporte() && { replyTo: { email: soporte(), name: 'Soporte ValleXpress' } }),
      to: [{ email: para, ...(nombre && { name: nombre }) }],
      subject: asunto,
      htmlContent: html,
      textContent: textoPlano(html),
      tags: ['vallexpress', ...etiquetas],
    }),
    signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) {
    const cuerpo = await r.json().catch(() => ({}));
    const e = new Error(`Brevo rechazó el correo (${r.status}): ${cuerpo.message || cuerpo.code || 'sin detalle'}`);
    e.code = 'CORREORECHAZADO';
    throw e;
  }
  return r.json();
}

// Para los avisos que no deben frenar la operación: si el correo falla, queda en TLOGMENSAJES y listo
function enviarSinEsperar(datos, contexto = {}) {
  enviar(datos).catch((e) => logMensaje({
    nivel: 'ADVERTENCIA', modulo: 'CORREO', accion: 'ENVIOFALLIDO', mensaje: `No se pudo enviar el correo "${datos.asunto}"`,
    detalle: { error: e.message, etiquetas: datos.etiquetas }, usuarioId: contexto.usuarioId,
  }));
}

const codigo = (c) => `<span style="font-size:34px;font-weight:800;letter-spacing:10px;color:${MARCA.texto};font-family:'Courier New',monospace">${escapar(c)}</span>`;
const dato = (etiqueta, valor) => `<div style="font-size:14px;color:${MARCA.suave};margin:2px 0">${escapar(etiqueta)}: <strong style="color:${MARCA.texto};font-size:16px">${escapar(valor)}</strong></div>`;
const ROLES = { cliente: 'cliente', vendedor: 'vendedor (negocio)', repartidor: 'repartidor', administrador: 'administrador' };

// ---------------------------------------------------------------------------------------------
// Correos de la app
// ---------------------------------------------------------------------------------------------
const codigoVerificacion = (para, cod, nombre) => enviar({
  para, nombre, asunto: `${cod} es tu código de ValleXpress`, etiquetas: ['verificacion'],
  html: plantilla({
    titulo: 'Confirma tu correo', saludo: `¡Hola ${nombre || ''}!`.replace(' !', '!'),
    parrafos: ['Gracias por unirte a ValleXpress. Escribe este código en la app para confirmar que este correo es tuyo:'],
    destacado: codigo(cod), notaDestacado: 'Vence en 15 minutos',
    avisoFinal: 'Si no estás creando una cuenta, ignora este correo: nadie podrá usar tu dirección sin este código.',
  }),
});

const codigoReset = (para, cod) => enviar({
  para, asunto: `${cod} es tu código para cambiar la contraseña`, etiquetas: ['reset'],
  html: plantilla({
    titulo: 'Recupera tu contraseña',
    parrafos: ['Pediste cambiar la contraseña de tu cuenta. Escribe este código en la app:'],
    destacado: codigo(cod), notaDestacado: 'Vence en 10 minutos',
    avisoFinal: 'Si no fuiste tú, ignora este correo: tu contraseña sigue igual. Al cambiarla también se desbloquea tu cuenta si estaba bloqueada por intentos fallidos.',
  }),
});

// Cuenta creada por el administrador: usuario y contraseña temporal para entrar por primera vez
const bienvenida = ({ para, nombre, usuario, rol, claveTemporal }) => enviarSinEsperar({
  para, nombre, asunto: '¡Bienvenido a ValleXpress! Ya tienes tu cuenta', etiquetas: ['bienvenida'],
  html: plantilla({
    titulo: 'Tu cuenta está lista', saludo: `¡Hola ${nombre}!`,
    parrafos: [`El equipo de ValleXpress creó tu cuenta de <strong>${escapar(ROLES[rol] || rol)}</strong>. Estos son tus datos para entrar a la app:`],
    destacado: dato('Usuario', usuario) + dato('Correo', para) + (claveTemporal ? dato('Contraseña temporal', claveTemporal) : ''),
    avisoFinal: 'Por tu seguridad, cambia la contraseña apenas entres: Perfil → Configuración → Cambiar contraseña.',
  }),
}, { usuarioId: usuario });

const bloqueoTemporal = ({ para, nombre, minutos }) => enviarSinEsperar({
  para, nombre, asunto: 'Bloqueamos tu cuenta por seguridad', etiquetas: ['seguridad'],
  html: plantilla({
    titulo: 'Detectamos varios intentos fallidos', saludo: `Hola ${nombre},`,
    parrafos: [`Alguien escribió mal la contraseña de tu cuenta varias veces seguidas, así que la bloqueamos <strong>${minutos} minutos</strong> para protegerla.`,
      'Si fuiste tú, espera ese tiempo o recupera tu contraseña desde "¿Olvidaste tu contraseña?" en la app: al cambiarla, tu cuenta se desbloquea al instante.'],
    avisoFinal: 'Si no fuiste tú, cambia tu contraseña cuanto antes.',
  }),
});

// Avisos del administrador sobre la cuenta (bloqueo, baja, reactivación, contraseña nueva)
const avisoCuenta = ({ para, nombre, asunto, titulo, parrafos, avisoFinal }) => enviarSinEsperar({
  para, nombre, asunto, etiquetas: ['cuenta'],
  html: plantilla({ titulo, saludo: `Hola ${nombre},`, parrafos, avisoFinal }),
});

module.exports = { configurado, soporte, enviar, codigoVerificacion, codigoReset, bienvenida, bloqueoTemporal, avisoCuenta, plantilla };
