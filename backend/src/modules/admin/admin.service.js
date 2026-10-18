const { Op, QueryTypes } = require('sequelize');
const { sequelize } = require('../../config/database');
const Usuario = require('../auth/usuario.model');
const UsuarioCuenta = require('../auth/usuarioCuenta.model');
const UsuarioAcceso = require('../auth/usuarioAcceso.model');
const Persona = require('../auth/persona.model');
const Telefono = require('../telefonos/telefono.model');
const AuthService = require('../auth/auth.service');
const ArchivoService = require('../../shared/services/archivo.service');
const { hashClave } = require('../../shared/utils/clave');
const { normalizarEmail, normalizarTelefono } = require('../../shared/utils/normalizers');
const Correo = require('../../shared/services/correo.service');
const { Negocio, NegocioEstado } = require('../negocios/negocio.model');
const NegocioService = require('../negocios/negocio.service');
const { Repartidor, RepartidorEstado } = require('../repartidores/repartidor.model');
const RepartidorService = require('../repartidores/repartidor.service');
const NotificacionService = require('../notificaciones/notificacion.service');
const SesionService = require('../../shared/services/sesion.service');
const ConfiguracionService = require('../../shared/services/configuracion.service');
const PerfilesService = require('../../shared/services/perfiles.service');
const TarifasService = require('../../shared/services/tarifas.service');
const ZonaService = require('../../shared/services/zona.service');
const SuscripcionService = require('../suscripciones/suscripcion.service');
const DocumentosService = require('../repartidores/documentos.service');
const AppError = require('../../shared/errors/AppError');
const withTransaction = require('../../shared/helpers/withTransaction');
const { auditar } = require('../../shared/services/log.service');
const { APROBACION, APROBACIONAAPI, ESTADOPEDIDO: E, ESTADOPEDIDOAAPI, ROLAAPI, APIAROL, VEHICULOAAPI } = require('../../shared/constants/codigos');
require('../pedidos/pedido.model');      // asegura la asociación Negocio -> dueño

// Panel del ADMINISTRADOR: métricas, aprobación de negocios y repartidores, usuarios y configuración.
// Cada cambio queda en la auditoría con quién lo hizo y, si aplica, el motivo.

const VIGENTE = "'2999-12-31 00:00:00-05'";
const ZONA = 'America/Guayaquil';
const num = (v) => (v === null || v === undefined ? null : Number(v));
const APIAAPROBACION = Object.freeze(Object.fromEntries(Object.entries(APROBACIONAAPI).map(([c, t]) => [t, c])));
const VENDIDOS = [E.ENTREGADO, E.RECIBIDO];

const consulta = (sql, replacements = {}) => sequelize.query(sql, { replacements, type: QueryTypes.SELECT });

function paginar(query) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(50, Math.max(1, parseInt(query.limit, 10) || 20));
  return { page, limit, offset: (page - 1) * limit };
}
const paginacion = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit), hasNext: page * limit < total });
const textoBusqueda = (q) => `%${String(q).trim().replace(/[%_]/g, '\\$&')}%`;
const conteo = (filas, aTexto) => Object.fromEntries(filas.map((f) => [aTexto(f.clave), Number(f.total)]));

// ---------------------------------------------------------------------------------------------
// Resumen: lo que el administrador ve al entrar
// ---------------------------------------------------------------------------------------------
async function resumen() {
  const vendidos = VENDIDOS.map((c) => `'${c}'`).join(',');
  const [hoy] = await consulta(`
    SELECT COUNT(*) AS pedidos,
           COUNT(*) FILTER (WHERE cestatuspedido IN (${vendidos})) AS entregados,
           COALESCE(SUM(total) FILTER (WHERE cestatuspedido IN (${vendidos})), 0) AS ventas,
           COALESCE(SUM(costoenvio) FILTER (WHERE cestatuspedido IN (${vendidos})), 0) AS envios,
           COALESCE(SUM(comision) FILTER (WHERE cestatuspedido IN (${vendidos})), 0) AS comisiones
      FROM tpedidos
     WHERE fhasta = ${VIGENTE} AND (fpedido AT TIME ZONE :zona)::date = (now() AT TIME ZONE :zona)::date`, { zona: ZONA });

  // Ventas de los últimos 7 días (incluye los días sin ventas, para la gráfica)
  const dias = await consulta(`
    SELECT to_char(d.dia, 'YYYY-MM-DD') AS dia, COUNT(p.cpedido) AS pedidos, COALESCE(SUM(p.total), 0) AS ventas,
           COALESCE(SUM(p.comision), 0) AS comisiones
      FROM generate_series((now() AT TIME ZONE :zona)::date - 6, (now() AT TIME ZONE :zona)::date, interval '1 day') AS d(dia)
      LEFT JOIN tpedidos p ON p.fhasta = ${VIGENTE} AND p.cestatuspedido IN (${vendidos}) AND (p.fpedido AT TIME ZONE :zona)::date = d.dia
     GROUP BY d.dia ORDER BY d.dia`, { zona: ZONA });

  const enCurso = await consulta(`SELECT cestatuspedido AS clave, COUNT(*) AS total FROM tpedidos
     WHERE fhasta = ${VIGENTE} AND cestatuspedido IN ('${E.PENDIENTE}','${E.CONFIRMADO}','${E.PREPARANDO}','${E.LISTO}','${E.ENCAMINO}','${E.RECOGIDO}')
     GROUP BY cestatuspedido`);

  const mejores = await consulta(`
    SELECT n.cnegocio AS id, n.nombre, COUNT(p.cpedido) AS pedidos, COALESCE(SUM(p.total), 0) AS ventas
      FROM tpedidos p JOIN tnegocios n ON n.cnegocio = p.cnegocio AND n.fhasta = ${VIGENTE}
     WHERE p.fhasta = ${VIGENTE} AND p.cestatuspedido IN (${vendidos}) AND p.fpedido >= now() - interval '30 days'
     GROUP BY n.cnegocio, n.nombre ORDER BY ventas DESC LIMIT 5`);

  const usuarios = await consulta('SELECT rol AS clave, COUNT(*) AS total FROM vusuarios GROUP BY rol');
  const negocios = await consulta(`SELECT cestatusaprobacion AS clave, COUNT(*) AS total FROM tnegocios WHERE fhasta = ${VIGENTE} GROUP BY cestatusaprobacion`);
  const repartidores = await consulta(`SELECT cestatusaprobacion AS clave, COUNT(*) AS total FROM trepartidores WHERE fhasta = ${VIGENTE} GROUP BY cestatusaprobacion`);
  const [enLinea] = await consulta('SELECT COUNT(*) AS total FROM trepartidoresestado WHERE estadisponible');
  const comprobantes = { total: await SuscripcionService.contarPorRevisar() };
  // Lo que ValleXpress cobró de suscripciones (pagos aprobados: la plata que de verdad entró)
  const [cobrado] = await consulta(`
    SELECT COALESCE(SUM(monto) FILTER (WHERE (frevision AT TIME ZONE :zona)::date = (now() AT TIME ZONE :zona)::date), 0) AS hoy,
           COALESCE(SUM(monto) FILTER (WHERE (frevision AT TIME ZONE :zona)::date >= (now() AT TIME ZONE :zona)::date - 6), 0) AS semana,
           COALESCE(SUM(monto) FILTER (WHERE (frevision AT TIME ZONE :zona)::date >= (now() AT TIME ZONE :zona)::date - 29), 0) AS mes
      FROM tsuscripcionpagos WHERE estado = 'APROBADO'`, { zona: ZONA });
  const deudores = await SuscripcionService.bloqueados();

  const negociosPor = conteo(negocios, (c) => APROBACIONAAPI[c]);
  const repartidoresPor = conteo(repartidores, (c) => APROBACIONAAPI[c]);
  return {
    hoy: { pedidos: Number(hoy.pedidos), entregados: Number(hoy.entregados), ventas: num(hoy.ventas), envios: num(hoy.envios), comisiones: num(hoy.comisiones) },
    ultimos7Dias: dias.map((d) => ({ dia: d.dia, pedidos: Number(d.pedidos), ventas: num(d.ventas), comisiones: num(d.comisiones) })),
    pedidosEnCurso: conteo(enCurso, (c) => ESTADOPEDIDOAAPI[c]),
    mejoresNegocios: mejores.map((m) => ({ id: Number(m.id), nombre: m.nombre, pedidos: Number(m.pedidos), ventas: num(m.ventas) })),
    usuarios: conteo(usuarios, (c) => ROLAAPI[c]),
    negocios: negociosPor,
    repartidores: { ...repartidoresPor, enLinea: Number(enLinea.total) },
    pendientes: (negociosPor.pendiente || 0) + (repartidoresPor.pendiente || 0),
    comprobantesPorRevisar: Number(comprobantes.total),
    cobrado: { hoy: num(cobrado.hoy), semana: num(cobrado.semana), mes: num(cobrado.mes) },
    suscripcionesVencidas: deudores.size,
    correoConfigurado: Correo.configurado(),
  };
}

// ---------------------------------------------------------------------------------------------
// Detalle de cada cifra del resumen (como el estado de cuenta de un banco: al tocar la cifra, sus movimientos)
// ---------------------------------------------------------------------------------------------
// tipo: pedidos | ventas | ganancia | envios | encurso | enlinea · rango: hoy | semana (7 días) | mes (30 días)
// Todas responden igual para que la app las dibuje con una sola pantalla:
//   { tipo, rango, total: { etiqueta, valor, formato }, resumen: [{ etiqueta, valor, formato }],
//     secciones: [{ titulo, filas: [{ titulo, detalle, valor, formato, pedidoId?, estado?, fecha?, icono }] }] }
const TIPOSDETALLE = ['pedidos', 'ventas', 'ganancia', 'envios', 'encurso', 'enlinea'];
const RANGOS = { hoy: 0, semana: 6, mes: 29 };
const ENCURSODETALLE = [E.PENDIENTE, E.CONFIRMADO, E.PREPARANDO, E.LISTO, E.ENCAMINO, E.RECOGIDO];
const nombreDe = (n, a) => [n, a].filter(Boolean).join(' ').trim() || null;
const NOMBREVEHICULO = { moto: 'Moto', auto: 'Auto', camioneta: 'Camioneta', bicicleta: 'Bicicleta', a_pie: 'A pie' };

async function detalleCifra(tipo, rangoTexto = 'hoy') {
  if (!TIPOSDETALLE.includes(tipo)) throw AppError.notFound('Esa cifra no existe', 'CIFRANOENCONTRADA');
  const rango = Object.prototype.hasOwnProperty.call(RANGOS, rangoTexto) ? rangoTexto : 'hoy';
  const enRango = (col) => `(${col} AT TIME ZONE :zona)::date >= (now() AT TIME ZONE :zona)::date - ${RANGOS[rango]}`;
  const vendidos = VENDIDOS.map((c) => `'${c}'`).join(',');
  const enCurso = ENCURSODETALLE.map((c) => `'${c}'`).join(',');
  const dinero = (v) => Number(Number(v || 0).toFixed(2));
  const suma = (lista, campo) => lista.reduce((t, p) => t + Number(p[campo] || 0), 0);

  // Pedidos con su local, cliente y repartidor
  const pedidos = (filtro) => consulta(`
    SELECT p.cpedido AS id, p.cestatuspedido AS estado, p.fpedido AS fecha, p.total, p.subtotal, p.costoenvio, p.comision,
           n.cnegocio AS "negocioId", n.nombre AS negocio, c.nombres AS "cNombre", c.apellidos AS "cApellido",
           r.usuario AS repartidor, r.nombres AS "rNombre", r.apellidos AS "rApellido"
      FROM tpedidos p
      JOIN tnegocios n ON n.cnegocio = p.cnegocio AND n.fhasta = ${VIGENTE}
      LEFT JOIN vusuarios c ON c.usuario = p.cusuario
      LEFT JOIN vusuarios r ON r.usuario = p.cusuario_repartidor
     WHERE p.fhasta = ${VIGENTE} AND ${filtro}
     ORDER BY p.fpedido DESC LIMIT 300`, { zona: ZONA });

  // Agrupa pedidos por una clave (local o repartidor) y suma un campo (o solo cuenta)
  const agrupar = (lista, clave, nombre, campo, icono) => {
    const m = new Map();
    for (const p of lista) {
      const k = p[clave] ?? 'sin';
      const g = m.get(k) || { titulo: nombre(p), pedidos: 0, suma: 0 };
      g.pedidos += 1;
      g.suma += Number(campo ? p[campo] : 0);
      m.set(k, g);
    }
    return [...m.values()].sort((a, b) => b.suma - a.suma || b.pedidos - a.pedidos).map((g) => ({
      titulo: g.titulo, detalle: g.pedidos === 1 ? '1 pedido' : `${g.pedidos} pedidos`,
      valor: campo ? dinero(g.suma) : g.pedidos, formato: campo ? 'dinero' : 'numero', icono,
    }));
  };
  const filaPedido = (p, valor, detalle) => ({
    titulo: `#${p.id} · ${p.negocio}`, detalle, valor: dinero(valor), formato: 'dinero',
    pedidoId: Number(p.id), estado: ESTADOPEDIDOAAPI[p.estado], fecha: p.fecha, icono: 'pedido',
  });
  const cliente = (p) => nombreDe(p.cNombre, p.cApellido) || 'Cliente';
  const repartidor = (p) => nombreDe(p.rNombre, p.rApellido);
  const plata = (v) => `$${dinero(v).toFixed(2)}`;

  if (tipo === 'pedidos') {
    const lista = await pedidos(enRango('p.fpedido'));
    const cuenta = (codigos) => lista.filter((p) => codigos.includes(p.estado)).length;
    return {
      tipo, rango,
      total: { etiqueta: 'Pedidos', valor: lista.length, formato: 'numero' },
      resumen: [
        { etiqueta: 'Entregados', valor: cuenta(VENDIDOS), formato: 'numero' },
        { etiqueta: 'En curso', valor: cuenta(ENCURSODETALLE), formato: 'numero' },
        { etiqueta: 'Cancelados o rechazados', valor: lista.length - cuenta(VENDIDOS) - cuenta(ENCURSODETALLE), formato: 'numero' },
      ],
      secciones: [
        { titulo: 'Por local', filas: agrupar(lista, 'negocioId', (p) => p.negocio, null, 'local') },
        { titulo: 'Pedidos', filas: lista.map((p) => filaPedido(p, p.total, cliente(p))) },
      ],
    };
  }

  if (tipo === 'ventas') {
    const lista = await pedidos(`p.cestatuspedido IN (${vendidos}) AND ${enRango('p.fpedido')}`);
    const total = suma(lista, 'total');
    return {
      tipo, rango,
      total: { etiqueta: 'Vendido (productos + envío)', valor: dinero(total), formato: 'dinero' },
      resumen: [
        { etiqueta: 'Productos', valor: dinero(suma(lista, 'subtotal')), formato: 'dinero' },
        { etiqueta: 'Envíos', valor: dinero(suma(lista, 'costoenvio')), formato: 'dinero' },
        { etiqueta: 'Ticket promedio', valor: dinero(lista.length ? total / lista.length : 0), formato: 'dinero' },
      ],
      secciones: [
        { titulo: 'Por local', filas: agrupar(lista, 'negocioId', (p) => p.negocio, 'total', 'local') },
        { titulo: 'Pedidos entregados', filas: lista.map((p) => filaPedido(p, p.total, `${cliente(p)} · productos ${plata(p.subtotal)}`)) },
      ],
    };
  }

  // Ganancia de ValleXpress = suscripciones cobradas (pagos aprobados en el rango)
  if (tipo === 'ganancia') {
    const [{ desde }] = await consulta(`SELECT to_char((now() AT TIME ZONE :zona)::date - ${RANGOS[rango]}, 'YYYY-MM-DD') AS desde`, { zona: ZONA });
    const pagos = await SuscripcionService.cobrado({ desde });
    const { suscriptores } = await SuscripcionService.resumen();
    const porCobrar = suscriptores.reduce((t, s) => t + s.saldoPendiente, 0);
    const deTipo = (t) => pagos.filter((p) => p.tipo === t);
    return {
      tipo, rango,
      total: { etiqueta: 'Suscripciones cobradas', valor: dinero(suma(pagos, 'monto')), formato: 'dinero' },
      resumen: [
        { etiqueta: 'De vendedores', valor: dinero(suma(deTipo('vendedor'), 'monto')), formato: 'dinero' },
        { etiqueta: 'De repartidores', valor: dinero(suma(deTipo('repartidor'), 'monto')), formato: 'dinero' },
        { etiqueta: 'Por cobrar', valor: dinero(porCobrar), formato: 'dinero' },
      ],
      secciones: [
        {
          titulo: 'Pagos recibidos',
          filas: pagos.map((p) => ({
            titulo: p.nombre, detalle: `${p.tipo === 'vendedor' ? 'Vendedor' : 'Repartidor'} · ${p.nombreMes}${p.referencia ? ` · ${p.referencia}` : ''}`,
            valor: dinero(p.monto), formato: 'dinero', fecha: p.fecha, icono: 'pago',
          })),
        },
        {
          titulo: 'Con pagos pendientes',
          filas: suscriptores.filter((s) => s.saldoPendiente > 0).map((s) => ({
            titulo: s.nombre, detalle: `${s.tipo === 'vendedor' ? 'Vendedor' : 'Repartidor'}${s.bloqueado ? ' · vencida' : ' · por pagar'}`,
            valor: dinero(s.saldoPendiente), formato: 'dinero', icono: s.tipo === 'vendedor' ? 'local' : 'repartidor',
          })),
        },
      ],
    };
  }

  if (tipo === 'envios') {
    const lista = await pedidos(`p.cestatuspedido IN (${vendidos}) AND ${enRango('p.fpedido')}`);
    const total = suma(lista, 'costoenvio');
    return {
      tipo, rango,
      total: { etiqueta: 'Ganado por los repartidores', valor: dinero(total), formato: 'dinero' },
      resumen: [
        { etiqueta: 'Entregas', valor: lista.length, formato: 'numero' },
        { etiqueta: 'Promedio por envío', valor: dinero(lista.length ? total / lista.length : 0), formato: 'dinero' },
      ],
      secciones: [
        { titulo: 'Por repartidor', filas: agrupar(lista, 'repartidor', (p) => repartidor(p) || 'Sin repartidor', 'costoenvio', 'repartidor') },
        { titulo: 'Entregas', filas: lista.map((p) => filaPedido(p, p.costoenvio, repartidor(p) || 'Sin repartidor')) },
      ],
    };
  }

  if (tipo === 'encurso') {
    const lista = await pedidos(`p.cestatuspedido IN (${enCurso})`);
    const sinRepartidor = lista.filter((p) => !p.repartidor).length;
    return {
      tipo, rango: 'ahora',
      total: { etiqueta: 'Pedidos en curso ahora', valor: lista.length, formato: 'numero' },
      resumen: [
        { etiqueta: 'Con repartidor', valor: lista.length - sinRepartidor, formato: 'numero' },
        { etiqueta: 'Sin repartidor', valor: sinRepartidor, formato: 'numero' },
      ],
      secciones: [
        { titulo: 'Pedidos', filas: lista.map((p) => filaPedido(p, p.total, `${cliente(p)} · ${repartidor(p) ? `lo lleva ${repartidor(p)}` : 'sin repartidor'}`)) },
        { titulo: 'Por local', filas: agrupar(lista, 'negocioId', (p) => p.negocio, null, 'local') },
      ],
    };
  }

  // enlinea: repartidores conectados, si llevan un pedido y cuándo se actualizó su ubicación
  const filas = await consulta(`
    SELECT e.cusuario AS usuario, u.nombres, u.apellidos, t.numerotelefono AS telefono, r.ctipovehiculo AS vehiculo, r.placa,
           e.fubicacion, e.numeroentregas AS entregas,
           (SELECT p.cpedido FROM tpedidos p WHERE p.fhasta = ${VIGENTE} AND p.cusuario_repartidor = e.cusuario
               AND p.cestatuspedido IN (${enCurso}) ORDER BY p.fpedido DESC LIMIT 1) AS pedido
      FROM trepartidoresestado e
      JOIN vusuarios u ON u.usuario = e.cusuario
      LEFT JOIN trepartidores r ON r.cusuario = e.cusuario AND r.fhasta = ${VIGENTE}
      LEFT JOIN tpersonatelefonos t ON t.cpersona = u.cpersona AND t.esprincipal AND t.fhasta = ${VIGENTE}
     WHERE e.estadisponible
     ORDER BY pedido NULLS LAST, u.nombres`);
  const ocupados = filas.filter((f) => f.pedido).length;
  return {
    tipo, rango: 'ahora',
    total: { etiqueta: 'Repartidores en línea', valor: filas.length, formato: 'numero' },
    resumen: [
      { etiqueta: 'Llevando un pedido', valor: ocupados, formato: 'numero' },
      { etiqueta: 'Libres', valor: filas.length - ocupados, formato: 'numero' },
    ],
    secciones: [{
      titulo: 'En línea ahora',
      filas: filas.map((f) => ({
        titulo: nombreDe(f.nombres, f.apellidos) || f.usuario,
        detalle: [NOMBREVEHICULO[VEHICULOAAPI[f.vehiculo]], f.placa, f.telefono, f.pedido ? `lleva el pedido #${f.pedido}` : 'libre'].filter(Boolean).join(' · '),
        valor: Number(f.entregas || 0), formato: 'entregas',
        ...(f.pedido && { pedidoId: Number(f.pedido) }),
        fecha: f.fubicacion, icono: 'repartidor', ocupado: !!f.pedido,
      })),
    }],
  };
}

// ---------------------------------------------------------------------------------------------
// Negocios
// ---------------------------------------------------------------------------------------------
const contacto = (u) => u && { usuario: u.id, nombre: u.nombre, apellido: u.apellido, email: u.email, telefono: u.telefono, activo: u.activo };

const INCLUIRNEGOCIO = [{ model: NegocioEstado, as: 'estado' }, { model: Usuario, as: 'dueno', attributes: ['id', 'nombre', 'apellido', 'email', 'telefono', 'activo'] }];

async function negociosApi(filas, req) {
  const lista = await NegocioService.aApi(filas, req, { privado: true });
  return lista.map((n, i) => ({ ...n, aprobadoEn: filas[i].aprobadoEn, dueno: contacto(filas[i].dueno) }));
}

async function negocios(query, req) {
  const pag = paginar(query);
  const where = {};
  if (APIAAPROBACION[query.aprobacion]) where.aprobacion = APIAAPROBACION[query.aprobacion];
  if (query.q) where.nombre = { [Op.iLike]: textoBusqueda(query.q) };
  const { count, rows } = await Negocio.findAndCountAll({
    where,
    include: INCLUIRNEGOCIO,
    order: [['aprobacion', 'ASC'], ['nombre', 'ASC']],          // los pendientes ('001') primero
    limit: pag.limit,
    offset: pag.offset,
  });
  return { negocios: await negociosApi(rows, req), pagination: paginacion(pag, count) };
}

// Aviso al dueño o al repartidor según la decisión
const AVISOAPROBACION = {
  aprobado: ['¡Tu cuenta fue aprobada! 🎉', (que) => `${que} ya está activo en ValleXpress`],
  rechazado: ['Solicitud no aprobada', (que, motivo) => `${que} no fue aprobado${motivo ? `: ${motivo}` : ''}`],
  suspendido: ['Cuenta suspendida', (que, motivo) => `${que} fue suspendido${motivo ? `: ${motivo}` : ''}. Escríbenos si crees que es un error`],
  pendiente: ['Tu cuenta está en revisión', (que) => `${que} volvió a revisión`],
};

// Correo de la decisión: [asunto, título, párrafos]. "pendiente" (volver a revisión) no manda correo.
const CORREOAPROBACION = {
  aprobado: (que) => ['¡Tu cuenta de ValleXpress fue aprobada! 🎉', '¡Ya puedes empezar!', [`${que} fue aprobado y ya está activo en ValleXpress.`, 'Abre la app para empezar.']],
  rechazado: (que, motivo) => ['Tu solicitud en ValleXpress no fue aprobada', 'Revisamos tu solicitud', [`${que} no fue aprobado por ahora.`, motivo, 'Corrige tus datos en la app y pide una nueva revisión, o respóndenos a este correo si tienes dudas.']],
  suspendido: (que, motivo) => ['Tu cuenta de ValleXpress fue suspendida', 'Suspendimos tu cuenta', [`${que} fue suspendido y por ahora no recibirá pedidos.`, motivo, 'Si crees que es un error, respóndenos a este correo y lo revisamos.']],
};

const motivoLimpio = (estado, motivo) => (['rechazado', 'suspendido'].includes(estado) ? motivo.trim().slice(0, 300) : null);

function exigirMotivo(estado, motivo) {
  if (['rechazado', 'suspendido'].includes(estado) && !motivo?.trim()) {
    throw AppError.badRequest('Escribe el motivo: se le enviará al usuario', 'MOTIVOREQUERIDO');
  }
}

// Avisa la decisión dentro de la app (notificación en vivo) y por correo
async function avisarAprobacion({ io, usuarioId, tipo, estado, que, motivo, datos }) {
  const [titulo, mensaje] = AVISOAPROBACION[estado];
  await NotificacionService.notificar({ io, usuarioId, tipo: `${tipo}_${estado}`, titulo, mensaje: mensaje(que, motivo), datos });
  const correo = CORREOAPROBACION[estado];
  const u = correo && (await Usuario.findByPk(usuarioId, { attributes: ['id', 'nombre', 'email'] }));
  if (!u?.email) return;
  const [asunto, tituloCorreo, parrafos] = correo(que, motivo ? `Motivo: <strong>${motivo.replace(/[<>&]/g, '')}</strong>` : null);
  Correo.avisoCuenta({ para: u.email, nombre: u.nombre, asunto, titulo: tituloCorreo, parrafos: parrafos.filter(Boolean) });
}

async function cambiarAprobacionNegocio(admin, id, { estado, motivo }, req) {
  exigirMotivo(estado, motivo);
  const codigo = APIAAPROBACION[estado];
  const n = await withTransaction(async (t) => {
    const negocio = await Negocio.findOne({ where: { id }, transaction: t, lock: t.LOCK.UPDATE });
    if (!negocio) throw AppError.notFound('Negocio no encontrado', 'NEGOCIONOENCONTRADO');
    if (negocio.aprobacion === codigo) throw AppError.conflict(`El negocio ya está ${estado}`, 'SINCAMBIOS');
    await negocio.update({
      aprobacion: codigo,
      aprobadoEn: codigo === APROBACION.APROBADO ? new Date() : negocio.aprobadoEn,
      motivoAprobacion: motivoLimpio(estado, motivo),
    }, { transaction: t });
    // Un negocio que deja de estar aprobado se cierra: no puede recibir pedidos
    if (codigo !== APROBACION.APROBADO) await NegocioEstado.update({ abierto: false }, { where: { negocioId: id }, transaction: t });
    return negocio;
  }, { usuarioId: admin.id });

  auditar({ usuarioId: admin.id, accion: 'NEGOCIOAPROBACION', entidad: 'NEGOCIOS', entidadId: id, detalle: { estado, motivo: motivo || null }, req });
  await avisarAprobacion({ io: req.io, usuarioId: n.duenoId, tipo: 'negocio', estado, que: `Tu negocio "${n.nombre}"`, motivo: motivoLimpio(estado, motivo), datos: { negocioId: Number(id) } });
  const [actualizado] = await negociosApi([await Negocio.findOne({ where: { id }, include: INCLUIRNEGOCIO })], req);
  return actualizado;
}

// ---------------------------------------------------------------------------------------------
// Repartidores
// ---------------------------------------------------------------------------------------------
const INCLUIRREPARTIDOR = [{ model: RepartidorEstado, as: 'estado' }, { association: 'usuario', attributes: ['id', 'nombre', 'apellido', 'email', 'telefono', 'activo'] }];
const repartidorApi = (r) => ({ ...RepartidorService.aApi(r), aprobadoEn: r.aprobadoEn, contacto: contacto(r.usuario) });

async function repartidores(query) {
  const pag = paginar(query);
  const where = {};
  if (APIAAPROBACION[query.aprobacion]) where.aprobacion = APIAAPROBACION[query.aprobacion];
  if (query.q) where[Op.or] = [{ usuarioId: { [Op.iLike]: textoBusqueda(query.q) } }, { placa: { [Op.iLike]: textoBusqueda(query.q) } }];
  const { count, rows } = await Repartidor.findAndCountAll({ where, include: INCLUIRREPARTIDOR, order: [['aprobacion', 'ASC'], ['usuarioId', 'ASC']], limit: pag.limit, offset: pag.offset });
  const docs = await DocumentosService.resumenDe(rows);
  const ids = rows.map((r) => r.usuarioId);
  const adv = ids.length ? await consulta('SELECT cusuario, COUNT(*)::int AS n FROM trepartidoradvertencias WHERE cusuario IN (:ids) GROUP BY cusuario', { ids }) : [];
  const advDe = Object.fromEntries(adv.map((a) => [a.cusuario, a.n]));
  return { repartidores: rows.map((r) => ({ ...repartidorApi(r), documentos: docs[r.usuarioId], advertencias: advDe[r.usuarioId] || 0 })), pagination: paginacion(pag, count) };
}

async function cambiarAprobacionRepartidor(admin, usuarioId, { estado, motivo }, req) {
  exigirMotivo(estado, motivo);
  const codigo = APIAAPROBACION[estado];
  await withTransaction(async (t) => {
    const r = await Repartidor.findOne({ where: { usuarioId }, transaction: t, lock: t.LOCK.UPDATE });
    if (!r) throw AppError.notFound('Repartidor no encontrado', 'REPARTIDORNOENCONTRADO');
    if (r.aprobacion === codigo) throw AppError.conflict(`El repartidor ya está ${estado}`, 'SINCAMBIOS');
    if (codigo === APROBACION.APROBADO) {
      const cupo = await PerfilesService.cupoRepartidores();
      if (cupo.lleno) throw AppError.conflict(`El cupo está lleno (${cupo.ocupados} de ${cupo.limite} repartidores aprobados). Súbelo en Perfiles y permisos para aprobar a más`, 'CUPOSLLENOS');
    }
    await r.update({
      aprobacion: codigo,
      aprobadoEn: codigo === APROBACION.APROBADO ? new Date() : r.aprobadoEn,
      motivoAprobacion: motivoLimpio(estado, motivo),
    }, { transaction: t });
    // Si deja de estar aprobado, se desconecta: ya no recibe pedidos
    if (codigo !== APROBACION.APROBADO) await RepartidorEstado.update({ disponible: false, ultimoCambio: new Date() }, { where: { usuarioId }, transaction: t });
  }, { usuarioId: admin.id });

  auditar({ usuarioId: admin.id, accion: 'REPARTIDORAPROBACION', entidad: 'REPARTIDORES', entidadId: usuarioId, detalle: { estado, motivo: motivo || null }, req });
  await avisarAprobacion({ io: req.io, usuarioId, tipo: 'repartidor', estado, que: 'Tu perfil de repartidor', motivo: motivoLimpio(estado, motivo) });
  return repartidorApi(await Repartidor.findOne({ where: { usuarioId }, include: INCLUIRREPARTIDOR }));
}

// ---------------------------------------------------------------------------------------------
// Usuarios: buscar, ver, crear, editar, cambiar la clave o la foto, bloquear, dar de baja y reactivar
// ---------------------------------------------------------------------------------------------
// Estatus de la cuenta (TESTATUSUSUARIO). "Dar de baja" no borra nada: la cuenta queda inactiva con todo su
// historial (pedidos, calificaciones) y se puede reactivar.
const ESTATUS = Object.freeze({ activo: '001', inactivo: '002', bloqueado: '003' });
const ESTATUSAAPI = Object.freeze(Object.fromEntries(Object.entries(ESTATUS).map(([k, v]) => [v, k])));
const TIPODOCCEDULA = '001';

async function usuariosApi(filas, req) {
  const urls = await ArchivoService.mapaUrls(req, filas.map((u) => u.fotoId));
  return filas.map((u) => ({
    usuario: u.id, nombre: u.nombre, apellido: u.apellido, email: u.email, telefono: u.telefono, cedula: u.cedula,
    rol: u.tipoUsuario, activo: u.activo, estatus: ESTATUSAAPI[u.estatus] || 'activo', verificado: u.verificado,
    foto: urls[String(u.fotoId)]?.miniatura || urls[String(u.fotoId)]?.url || null,
    ultimaConexion: u.ultimaConexion, creadoEn: u.creadoEn,
  }));
}
const usuarioApi = async (u, req) => (await usuariosApi([u], req))[0];

async function exigirUsuario(usuarioId) {
  const u = await Usuario.findByPk(usuarioId);
  if (!u) throw AppError.notFound('Usuario no encontrado', 'USUARIONOENCONTRADO');
  return u;
}

// El administrador principal ("admin") y uno mismo no se pueden bloquear ni dar de baja (nadie quedaría a cargo)
function exigirNoProtegido(admin, usuarioId) {
  if (usuarioId === 'admin' || usuarioId === admin.id) {
    throw AppError.forbidden('Esta cuenta de administrador no se puede bloquear ni dar de baja', 'ADMINPROTEGIDO');
  }
}

async function usuarios(query, req) {
  const pag = paginar(query);
  const where = {};
  if (APIAROL[query.rol]) where.rol = APIAROL[query.rol];
  if (query.activo === 'true' || query.activo === 'false') where.activo = query.activo === 'true';
  if (query.q) {
    const t = textoBusqueda(query.q);
    where[Op.or] = [{ id: { [Op.iLike]: t } }, { nombre: { [Op.iLike]: t } }, { apellido: { [Op.iLike]: t } }, { email: { [Op.iLike]: t } }, { cedula: { [Op.iLike]: t } }];
  }
  const { count, rows } = await Usuario.findAndCountAll({ where, order: [['creadoEn', 'DESC']], limit: pag.limit, offset: pag.offset });
  return { usuarios: await usuariosApi(rows, req), pagination: paginacion(pag, count) };
}

const obtenerUsuario = async (usuarioId, req) => usuarioApi(await exigirUsuario(usuarioId), req);

// Crea una cuenta de cualquier rol (también otro administrador) sin pasar por la verificación del correo.
// El negocio o el perfil de reparto nacen ya aprobados: los crea el propio administrador.
async function crearUsuario(admin, datos, req) {
  const cuenta = await withTransaction((t) => AuthService.crearCuenta(datos.rol, datos, t, { aprobado: true }), { usuarioId: admin.id });
  auditar({ usuarioId: admin.id, accion: 'USUARIOCREADOADMIN', entidad: 'USUARIOS', entidadId: cuenta.id, detalle: { rol: datos.rol }, req });
  const u = await exigirUsuario(cuenta.id);
  // Le llegan por correo su usuario y la contraseña temporal (salvo que el admin prefiera dárselos en persona)
  if (datos.enviarCorreo !== false) {
    Correo.bienvenida({ para: u.email, nombre: u.nombre, usuario: u.id, rol: datos.rol, claveTemporal: datos.password });
  }
  return usuarioApi(u, req);
}

// Corrige los datos personales: nombre, apellido, correo, cédula y teléfono principal (sin repetir los de otros)
async function editarUsuario(admin, usuarioId, datos, req) {
  const u = await exigirUsuario(usuarioId);
  const email = datos.email !== undefined ? normalizarEmail(datos.email) : undefined;
  const telefono = datos.telefono !== undefined ? normalizarTelefono(datos.telefono) : undefined;
  const otraPersona = { [Op.ne]: u.personaId };
  if (email && email !== u.email && await Persona.findOne({ where: { correo: email, id: otraPersona } })) throw AppError.conflict('El email ya está registrado', 'EMAILDUPLICADO');
  if (datos.cedula && datos.cedula !== u.cedula && await Persona.findOne({ where: { tipoDoc: TIPODOCCEDULA, numeroDoc: datos.cedula, id: otraPersona } })) {
    throw AppError.conflict('La cédula ya está registrada', 'CEDULADUPLICADA');
  }
  if (telefono && telefono !== u.telefono && await Telefono.findOne({ where: { numero: telefono, personaId: otraPersona } })) throw AppError.conflict('El teléfono ya está registrado', 'TELEFONODUPLICADO');

  await withTransaction(async (t) => {
    const cambios = {
      ...(datos.nombre && { nombres: datos.nombre.trim() }),
      ...(datos.apellido && { apellidos: datos.apellido.trim() }),
      ...(email && email !== u.email && { correo: email }),
      ...(datos.cedula && datos.cedula !== u.cedula && { numeroDoc: datos.cedula }),
    };
    if (Object.keys(cambios).length) await Persona.update(cambios, { where: { id: u.personaId }, transaction: t });
    if (telefono && telefono !== u.telefono) {
      const principal = await Telefono.findOne({ where: { personaId: u.personaId, principal: true }, transaction: t });
      if (principal) await Telefono.update({ numero: telefono }, { where: { personaId: u.personaId, secuencia: principal.secuencia }, transaction: t });
      else await Telefono.create({ personaId: u.personaId, numero: telefono, principal: true }, { transaction: t });
    }
  }, { usuarioId: admin.id });

  auditar({ usuarioId: admin.id, accion: 'USUARIOEDITADOADMIN', entidad: 'USUARIOS', entidadId: usuarioId, detalle: { campos: Object.keys(datos) }, req });
  return usuarioApi(await exigirUsuario(usuarioId), req);
}

// Clave nueva (por ejemplo, si el usuario la olvidó y no tiene su correo): se cierran todas sus sesiones
async function ponerClave(admin, usuarioId, clave, req, { enviarCorreo = true } = {}) {
  const u = await exigirUsuario(usuarioId);
  const claveHash = await hashClave(clave);
  await withTransaction(async (t) => {
    await UsuarioCuenta.update({ claveHash, claveCambiadaEn: new Date() }, { where: { id: usuarioId }, transaction: t });
    await UsuarioAcceso.update({ intentos: 0, bloqueadoHasta: null }, { where: { id: usuarioId }, transaction: t });
    await SesionService.cerrarTodas(usuarioId, 'CLAVE', { transaction: t });
  }, { usuarioId: admin.id });
  if (req.io) req.io.in(`user:${usuarioId}`).disconnectSockets(true);
  auditar({ usuarioId: admin.id, accion: 'CLAVEPUESTAADMIN', entidad: 'USUARIOS', entidadId: usuarioId, req });
  if (enviarCorreo) {
    Correo.avisoCuenta({
      para: u.email, nombre: u.nombre, asunto: 'Tu contraseña de ValleXpress cambió', titulo: 'Tienes una contraseña nueva',
      parrafos: ['El equipo de ValleXpress te puso una contraseña nueva y cerró tus sesiones abiertas. Entra con ella:',
        `Usuario: <strong>${u.id}</strong><br>Contraseña: <strong>${clave.replace(/[<>&]/g, '')}</strong>`],
      avisoFinal: 'Cámbiala apenas entres: Perfil → Configuración → Cambiar contraseña. Si no pediste este cambio, escríbenos.',
    });
  }
  return usuarioApi(await exigirUsuario(usuarioId), req);
}

async function fotoUsuario(admin, usuarioId, base64, req) {
  await AuthService.subirFoto(usuarioId, base64, req, { actor: admin.id });
  return usuarioApi(await exigirUsuario(usuarioId), req);
}

// Cambia el estatus de la cuenta. Fuera de "activo" no puede entrar: se cierran sus sesiones, se corta su
// conexión en vivo y, si es repartidor, queda fuera de línea.
async function cambiarEstatus(admin, usuarioId, estatus, motivo, req) {
  const u = await exigirUsuario(usuarioId);
  if (estatus !== 'activo') exigirNoProtegido(admin, usuarioId);
  if (ESTATUSAAPI[u.estatus] === estatus) {
    const textos = { activo: 'La cuenta ya está activa', bloqueado: 'La cuenta ya está bloqueada', inactivo: 'La cuenta ya está dada de baja' };
    throw AppError.conflict(textos[estatus], 'SINCAMBIOS');
  }
  if (estatus !== 'activo' && !motivo?.trim()) throw AppError.badRequest('Escribe el motivo', 'MOTIVOREQUERIDO');

  await withTransaction(async (t) => {
    await UsuarioCuenta.update({ estatus: ESTATUS[estatus] }, { where: { id: usuarioId }, transaction: t });
    if (estatus !== 'activo') {
      await SesionService.cerrarTodas(usuarioId, estatus === 'bloqueado' ? 'BLOQUEO' : 'BAJA', { transaction: t });
      await RepartidorEstado.update({ disponible: false, ultimoCambio: new Date() }, { where: { usuarioId }, transaction: t });
    }
  }, { usuarioId: admin.id });

  if (estatus !== 'activo' && req.io) req.io.in(`user:${usuarioId}`).disconnectSockets(true);
  const accion = { activo: 'USUARIOREACTIVADO', bloqueado: 'USUARIOBLOQUEADO', inactivo: 'USUARIODADODEBAJA' }[estatus];
  auditar({ usuarioId: admin.id, accion, entidad: 'USUARIOS', entidadId: usuarioId, detalle: { motivo: motivo || null }, req });
  // Como ya no puede entrar a la app, se le avisa por correo (con el motivo y a quién escribir)
  const motivoHtml = motivo ? `Motivo: <strong>${motivo.trim().replace(/[<>&]/g, '')}</strong>` : null;
  const correo = {
    activo: ['Tu cuenta de ValleXpress está activa de nuevo', '¡Bienvenido de vuelta!', ['Reactivamos tu cuenta: ya puedes entrar a la app con tu usuario y tu contraseña de siempre.']],
    bloqueado: ['Tu cuenta de ValleXpress fue bloqueada', 'Bloqueamos tu cuenta', ['Por ahora no podrás entrar a la app.', motivoHtml, 'Si crees que es un error, respóndenos a este correo y lo revisamos.']],
    inactivo: ['Tu cuenta de ValleXpress fue dada de baja', 'Tu cuenta quedó inactiva', ['Dimos de baja tu cuenta; tu historial no se borró.', motivoHtml, 'Si quieres volver, respóndenos y la reactivamos.']],
  }[estatus];
  Correo.avisoCuenta({ para: u.email, nombre: u.nombre, asunto: correo[0], titulo: correo[1], parrafos: correo[2].filter(Boolean) });
  return usuarioApi(await exigirUsuario(usuarioId), req);
}

// Compatibilidad con PATCH /usuarios/:usuario/estado { activo }: activo = true reactiva, false bloquea
const cambiarEstadoUsuario = (admin, usuarioId, { activo, motivo }, req) =>
  cambiarEstatus(admin, usuarioId, activo ? 'activo' : 'bloqueado', motivo, req);

const darDeBaja = (admin, usuarioId, { motivo }, req) => cambiarEstatus(admin, usuarioId, 'inactivo', motivo, req);

// ---------------------------------------------------------------------------------------------
// Gestión de un negocio "como su dueño": el administrador usa las mismas rutas que el vendedor
// (datos, local, horario, abrir/cerrar, imágenes y productos). Cada cambio queda auditado a su nombre.
// ---------------------------------------------------------------------------------------------
async function resolverDueno(req) {
  const negocio = await Negocio.findOne({ where: { id: req.params.negocioId }, attributes: ['id', 'duenoId'] });
  if (!negocio) throw AppError.notFound('Negocio no encontrado', 'NEGOCIONOENCONTRADO');
  req.duenoId = negocio.duenoId;
  if (req.method !== 'GET') {
    auditar({ usuarioId: req.usuario.id, accion: 'NEGOCIOGESTIONADMIN', entidad: 'NEGOCIOS', entidadId: negocio.id, detalle: { metodo: req.method, ruta: req.path }, req });
  }
}

// Vehículo, placa y color de un repartidor
async function editarRepartidor(admin, usuarioId, datos, req) {
  await RepartidorService.exigirPerfil(usuarioId);
  await RepartidorService.actualizar(usuarioId, datos, req, { comoAdmin: true });
  auditar({ usuarioId: admin.id, accion: 'REPARTIDOREDITADOADMIN', entidad: 'REPARTIDORES', entidadId: usuarioId, detalle: datos, req });
  return repartidorApi(await Repartidor.findOne({ where: { usuarioId }, include: INCLUIRREPARTIDOR }));
}

// ---------------------------------------------------------------------------------------------
// Tarifas: envío por distancia y comisión de ValleXpress
// ---------------------------------------------------------------------------------------------
async function cambiarTarifas(admin, cambios, req) {
  const hechos = await withTransaction((t) => TarifasService.fijar(cambios, { transaction: t }), { usuarioId: admin.id });
  ConfiguracionService.limpiarCache();
  if (Object.keys(hechos).length) auditar({ usuarioId: admin.id, accion: 'TARIFASCAMBIADAS', entidad: 'CONFIGURACIONES', entidadId: 'TARIFAS', detalle: hechos, req });
  return TarifasService.tarifas();
}

// Suscripción: cuotas, día límite para pagar, desde qué mes se cobra y la cuenta donde transferir
async function cambiarConfigSuscripciones(admin, cambios, req) {
  const hechos = await withTransaction((t) => SuscripcionService.fijarConfig(cambios, { transaction: t }), { usuarioId: admin.id });
  ConfiguracionService.limpiarCache();
  if (Object.keys(hechos).length) auditar({ usuarioId: admin.id, accion: 'CONFIGSUSCRIPCIONES', entidad: 'CONFIGURACIONES', entidadId: 'SUSCRIPCIONES', detalle: hechos, req });
  return SuscripcionService.config();
}

// Zona de servicio (por ahora una sola ciudad)
async function cambiarZona(admin, cambios, req) {
  const hechos = await withTransaction((t) => ZonaService.fijar(cambios, { transaction: t }), { usuarioId: admin.id });
  ConfiguracionService.limpiarCache();
  if (Object.keys(hechos).length) auditar({ usuarioId: admin.id, accion: 'ZONACAMBIADA', entidad: 'CONFIGURACIONES', entidadId: 'ZONA', detalle: hechos, req });
  return ZonaService.zona();
}

// ---------------------------------------------------------------------------------------------
// Perfiles y permisos
// ---------------------------------------------------------------------------------------------
// Por perfil (cliente, vendedor, repartidor): si puede registrarse desde la app y, para vendedor y repartidor,
// si nace aprobado o espera la revisión. Con cuántas cuentas tiene y cuántas solicitudes esperan.
async function perfiles() {
  const filas = await sequelize.query(
    `SELECT crol, COUNT(*) AS total, COUNT(*) FILTER (WHERE cestatususuario = :activo) AS activos
       FROM tusuarios WHERE fhasta = ${VIGENTE} GROUP BY crol`,
    { replacements: { activo: ESTATUS.activo }, type: QueryTypes.SELECT },
  );
  const cuentas = Object.fromEntries(filas.map((f) => [ROLAAPI[f.crol], { total: Number(f.total), activos: Number(f.activos) }]));
  const pendientes = {
    vendedor: await Negocio.count({ where: { aprobacion: APROBACION.PENDIENTE } }),
    repartidor: await Repartidor.count({ where: { aprobacion: APROBACION.PENDIENTE } }),
  };
  const cupo = await PerfilesService.cupoRepartidores();
  return (await PerfilesService.permisos()).map((p) => ({
    ...p,
    cuentas: cuentas[p.rol] || { total: 0, activos: 0 },
    ...(PerfilesService.conAprobacion(p.rol) && { pendientes: pendientes[p.rol] }),
    ...(p.rol === 'repartidor' && { cupo }),
  }));
}

// WhatsApp de soporte (se muestra a quien no encuentra cupo)
async function cambiarSoporte(admin, { whatsapp }, req) {
  await withTransaction((t) => ConfiguracionService.fijar('SOPORTEWHATSAPP', String(whatsapp || '').trim(), { transaction: t }), { usuarioId: admin.id });
  ConfiguracionService.limpiarCache();
  auditar({ usuarioId: admin.id, accion: 'SOPORTECAMBIADO', entidad: 'CONFIGURACIONES', entidadId: 'SOPORTEWHATSAPP', detalle: { whatsapp }, req });
  return PerfilesService.soporte();
}

const perfil = async (rol) => (await perfiles()).find((p) => p.rol === rol);

// Cambia los permisos de un perfil. Con aprobarPendientes, además aprueba las solicitudes que estaban esperando
// (cada una recibe su aviso y su correo, igual que si se aprobara a mano).
async function cambiarPerfil(admin, rol, { registroAbierto, aprobacionAutomatica, aprobarPendientes, cupo }, req) {
  if (aprobacionAutomatica !== undefined && !PerfilesService.conAprobacion(rol)) {
    throw AppError.badRequest('Este perfil no pasa por aprobación', 'SINAPROBACION');
  }
  if (cupo !== undefined && rol !== 'repartidor') throw AppError.badRequest('Solo los repartidores tienen cupo', 'SINCUPO');
  const cambios = await withTransaction(async (t) => {
    const hechos = await PerfilesService.fijar(rol, { registroAbierto, aprobacionAutomatica }, { transaction: t });
    if (cupo !== undefined && Number(cupo) !== (await PerfilesService.cupoRepartidores()).limite) {
      await ConfiguracionService.fijar('CUPOREPARTIDORES', Number(cupo), { transaction: t });
      hechos.cupo = Number(cupo);
    }
    return hechos;
  }, { usuarioId: admin.id });
  ConfiguracionService.limpiarCache();
  if (Object.keys(cambios).length) {
    auditar({ usuarioId: admin.id, accion: 'PERFILCAMBIADO', entidad: 'CONFIGURACIONES', entidadId: rol, detalle: cambios, req });
  }

  let aprobados = 0;
  if (aprobarPendientes && PerfilesService.conAprobacion(rol)) {
    if (rol === 'vendedor') {
      const lista = await Negocio.findAll({ where: { aprobacion: APROBACION.PENDIENTE }, attributes: ['id'], order: [['id', 'ASC']] });
      for (const n of lista) {
        await cambiarAprobacionNegocio(admin, n.id, { estado: 'aprobado' }, req);
        aprobados += 1;
      }
    } else {
      const lista = await Repartidor.findAll({ where: { aprobacion: APROBACION.PENDIENTE }, attributes: ['usuarioId'], order: [['usuarioId', 'ASC']] });
      for (const r of lista) {
        if ((await PerfilesService.cupoRepartidores()).lleno) break;    // los demás siguen esperando cupo
        await cambiarAprobacionRepartidor(admin, r.usuarioId, { estado: 'aprobado' }, req);
        aprobados += 1;
      }
    }
  }
  return { perfil: await perfil(rol), aprobados };
}

module.exports = {
  detalleCifra,
  resumen, negocios, cambiarAprobacionNegocio, repartidores, cambiarAprobacionRepartidor,
  usuarios, obtenerUsuario, crearUsuario, editarUsuario, ponerClave, fotoUsuario, cambiarEstadoUsuario, darDeBaja,
  resolverDueno, editarRepartidor, perfiles, cambiarPerfil, cambiarTarifas,
  tarifas: () => TarifasService.tarifas(),
  zona: () => ZonaService.zona(), cambiarZona, cambiarConfigSuscripciones, cambiarSoporte,
};
