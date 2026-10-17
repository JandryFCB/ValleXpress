const express = require('express');
const LegalService = require('./legal.service');
const Correo = require('../../shared/services/correo.service');
const asyncHandler = require('../../shared/helpers/asyncHandler');

// PÁGINAS WEB PÚBLICAS de los documentos legales (sin sesión). Son las URL que se publican en Google Play:
//   /legal                    índice
//   /legal/privacidad         política de privacidad (y /legal/terminos-cliente, -vendedor, -repartidor)
//   /legal/eliminar-cuenta    cómo eliminar la cuenta y qué datos se borran (Google Play lo exige)
// HTML liviano, sin scripts, con el mismo texto que ve la app.

const router = express.Router();

const escapar = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const enLinea = (s) => escapar(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

function bloquesAHtml(bloques) {
  return bloques.map((b) => {
    if (b.tipo === 'titulo') return `<h2>${enLinea(b.texto)}</h2>`;
    if (b.tipo === 'parrafo') return `<p>${enLinea(b.texto)}</p>`;
    const etiqueta = b.ordenada ? 'ol' : 'ul';
    const items = b.items.map((i) => `<li>${enLinea(i.texto)}${i.sub.length ? `<ul>${i.sub.map((s) => `<li>${enLinea(s)}</li>`).join('')}</ul>` : ''}${i.notas.map((n) => `<p>${enLinea(n)}</p>`).join('')}</li>`).join('');
    return `<${etiqueta}>${items}</${etiqueta}>`;
  }).join('\n');
}

const pagina = (titulo, cuerpo) => `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapar(titulo)} · ValleXpress</title>
<style>
  :root { color-scheme: light dark; --verde: #16a34a; --fondo: #f6f8fa; --tarjeta: #fff; --texto: #1f2937; --suave: #6b7280; }
  @media (prefers-color-scheme: dark) { :root { --fondo: #0b1a2b; --tarjeta: #12263d; --texto: #e5e7eb; --suave: #9ca3af; } }
  body { margin: 0; background: var(--fondo); color: var(--texto); font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; overflow-wrap: break-word; }
  main { max-width: 760px; margin: 0 auto; padding: 24px 18px 48px; }
  header { display: flex; align-items: center; gap: 10px; margin-bottom: 18px; font-weight: 800; font-size: 20px; color: var(--verde); }
  article { background: var(--tarjeta); border-radius: 16px; padding: 22px 22px 8px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  h1 { font-size: 26px; line-height: 1.25; margin: 0 0 6px; }
  h2 { font-size: 19px; margin: 28px 0 8px; }
  .meta { color: var(--suave); font-size: 14px; margin-bottom: 18px; }
  a { color: var(--verde); }
  li { margin: 4px 0; }
  li > p { margin: 6px 0; }
  .indice a { display: block; padding: 14px 0; border-bottom: 1px solid rgba(127,127,127,.2); font-weight: 600; text-decoration: none; }
  .indice span { display: block; color: var(--suave); font-weight: 400; font-size: 14px; }
  footer { color: var(--suave); font-size: 13px; text-align: center; margin-top: 24px; }
</style></head>
<body><main><header>ValleXpress</header><article>${cuerpo}</article>
<footer>ValleXpress · Yantzaza, Ecuador · <a href="/legal">Documentos legales</a></footer></main></body></html>`;

const fecha = (iso) => {
  const [a, m, d] = String(iso).split('-').map(Number);
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  return a && m && d ? `${d} de ${meses[m - 1]} de ${a}` : iso;
};

router.get('/', (req, res) => {
  const docs = LegalService.lista();
  res.type('html').send(pagina('Documentos legales', `<h1>Documentos legales</h1>
    <div class="indice">${docs.map((d) => `<a href="/legal/${d.id}">${escapar(d.titulo)}<span>Versión ${escapar(d.version)} · vigente desde el ${fecha(d.vigencia)}</span></a>`).join('')}
    <a href="/legal/eliminar-cuenta">Eliminar mi cuenta<span>Cómo eliminar tu cuenta y qué datos borramos</span></a></div>`));
});

router.get('/eliminar-cuenta', asyncHandler(async (req, res) => {
  const correo = Correo.soporte();
  const contacto = correo ? `<a href="mailto:${escapar(correo)}?subject=Eliminar%20mi%20cuenta">${escapar(correo)}</a>` : 'nuestro correo de soporte';
  res.type('html').send(pagina('Eliminar mi cuenta', `<h1>Eliminar mi cuenta de ValleXpress</h1>
    <p class="meta">Aplicación ValleXpress · responsable: Jandry Franklin Cayapa Baque</p>
    <h2>Desde la app (inmediato)</h2>
    <ol><li>Abre ValleXpress e inicia sesión.</li><li>Ve a <strong>Perfil → Configuración → Eliminar mi cuenta</strong>.</li>
    <li>Confirma con tu contraseña.</li></ol>
    <p>No puedes eliminarla mientras tengas un pedido en curso o, si eres un negocio, comisiones por pagar.</p>
    <h2>Si ya no tienes la app</h2>
    <p>Escríbenos a ${contacto} <strong>desde el correo con el que te registraste</strong>, con el asunto "Eliminar mi cuenta". La eliminamos en un máximo de 15 días y te confirmamos por correo.</p>
    <h2>Qué datos borramos</h2>
    <ul><li>Nombre, cédula, correo, teléfono, fecha de nacimiento y foto de perfil, también de nuestros historiales internos.</li>
    <li>Direcciones guardadas, vehículo y placa, recorridos de entregas y equipos registrados para notificaciones.</li>
    <li>Tus sesiones se cierran en todos los equipos.</li></ul>
    <h2>Qué conservamos</h2>
    <ul><li>Los pedidos, pagos y comisiones, <strong>sin tus datos de contacto</strong>, hasta 7 años, porque son registros contables que exige la normativa tributaria.</li>
    <li>Las copias de seguridad se renuevan solas: los datos eliminados desaparecen de ellas en un máximo de 30 días.</li></ul>
    <p>Más detalles en la <a href="/legal/privacidad">Política de privacidad</a>.</p>`));
}));

router.get('/:id', asyncHandler(async (req, res, next) => {
  if (!LegalService.IDS.includes(req.params.id)) return next();
  const d = await LegalService.documento(req.params.id);
  res.type('html').send(pagina(d.titulo, `<h1>${escapar(d.titulo)}</h1><p class="meta">Versión ${escapar(d.version)} · vigente desde el ${fecha(d.vigencia)}</p>${bloquesAHtml(d.bloques)}`));
}));

module.exports = router;
