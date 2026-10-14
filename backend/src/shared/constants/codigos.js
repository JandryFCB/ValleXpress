// Códigos de los catálogos de la BD. UNA sola fuente de verdad: en el código nunca se escribe '006',
// se escribe ESTADOPEDIDO.ENCAMINO. Deben coincidir con los INSERT de database/migraciones/.

const ROLES = Object.freeze({
  CLIENTE: '001',
  VENDEDOR: '002',
  REPARTIDOR: '003',
  ADMINISTRADOR: '004',
});

// Tipos de los catálogos T (códigos de 3 letras). LOC (local del negocio) lo maneja el módulo de vendedores,
// por eso el cliente no puede elegirlo como tipo de dirección.
// La app habla en texto de 3 letras ('MOV', 'DOM'...); la BD guarda el código del catálogo ('001'...).
const TIPOTELEFONO = Object.freeze({ MOV: '001', CAS: '002', TRA: '003', WAP: '004' });
const TIPODIRECCION = Object.freeze({ DOM: '001', TRA: '002', FAM: '003', OTR: '004', LOC: '005' });
const invertir = (o) => Object.freeze(Object.fromEntries(Object.entries(o).map(([k, v]) => [v, k])));
const TIPOTELEFONOAAPI = invertir(TIPOTELEFONO);        // '001' -> 'MOV'
const TIPODIRECCIONAAPI = invertir(TIPODIRECCION);      // '001' -> 'DOM'
const TIPOSTELEFONO = Object.freeze(Object.keys(TIPOTELEFONO));
const TIPOSDIRECCION = Object.freeze(['DOM', 'TRA', 'FAM', 'OTR']);   // el cliente no elige LOC (local del negocio)
const TIPODIRECCIONLOCAL = TIPODIRECCION.LOC;           // código de BD del local del negocio

const ESTADOPEDIDO = Object.freeze({
  PENDIENTE: '001',
  CONFIRMADO: '002',
  PREPARANDO: '003',
  LISTO: '004',
  ENCAMINO: '005',          // el repartidor aceptó y va al negocio
  RECOGIDO: '006',          // lo recogió y lo lleva al cliente
  ENTREGADO: '007',
  RECIBIDO: '008',
  RECHAZADO: '009',
  CANCELADO: '010',
});

// Estatus de un producto (catálogo TESTATUSPRODUCTO). La app habla en texto: 'disponible', 'agotado', 'oculto'.
const ESTADOPRODUCTO = Object.freeze({
  DISPONIBLE: '001',
  AGOTADO: '002',
  OCULTO: '003',
});
const ESTADOPRODUCTOAAPI = Object.freeze({ '001': 'disponible', '002': 'agotado', '003': 'oculto' });
const APIAESTADOPRODUCTO = Object.freeze({ disponible: '001', agotado: '002', oculto: '003' });

const ESTADOPAGO = Object.freeze({
  PENDIENTE: '001',
  APROBADO: '002',
  RECHAZADO: '003',
  REEMBOLSADO: '004',
  REEMBOLSOPARCIAL: '005',
  CANCELADO: '006',
});

// Aprobación de un negocio (catálogo TESTATUSAPROBACION)
const APROBACION = Object.freeze({
  PENDIENTE: '001',
  APROBADO: '002',
  RECHAZADO: '003',
  SUSPENDIDO: '004',
});
const APROBACIONAAPI = Object.freeze({ '001': 'pendiente', '002': 'aprobado', '003': 'rechazado', '004': 'suspendido' });

const METODOPAGO = Object.freeze({
  EFECTIVO: '001',
  TRANSFERENCIA: '002',
  TARJETA: '003',
  PAYPAL: '004',
});

const TIPOVEHICULO = Object.freeze({
  MOTOCICLETA: '001',
  AUTOMOVIL: '002',
  CAMIONETA: '003',
  BICICLETA: '004',
  APIE: '005',
});

const CATEGORIA = Object.freeze({
  COMIDA: '001',
  BEBIDAS: '002',
  POSTRES: '003',
  PANADERIA: '004',
  SUPERMERCADO: '005',
  FARMACIA: '006',
  MASCOTAS: '007',
  OTROS: '099',
});

// Propósito de un código de verificación (catálogo TPROPOSITOSCODIGO)
const PROPOSITOCODIGO = Object.freeze({
  EMAIL: '001',
  RESETCLAVE: '002',
});

// --- Traducción con la API actual -------------------------------------------------------------
// La app Flutter todavía habla en texto ('cliente', 'vendedor'...). Estas tablas convierten
// entre ese texto y el código de la BD. Cuando la app migre a códigos, se eliminan.
const ROLAAPI = Object.freeze({
  [ROLES.CLIENTE]: 'cliente',
  [ROLES.VENDEDOR]: 'vendedor',
  [ROLES.REPARTIDOR]: 'repartidor',
  [ROLES.ADMINISTRADOR]: 'administrador',
});
const APIAROL = Object.freeze(Object.fromEntries(Object.entries(ROLAAPI).map(([cod, txt]) => [txt, cod])));

// Estados del pedido: la app habla en texto ('en_camino', 'recogido'...); la BD guarda el código.
const ESTADOPEDIDOAAPI = Object.freeze({
  [ESTADOPEDIDO.PENDIENTE]: 'pendiente',
  [ESTADOPEDIDO.CONFIRMADO]: 'confirmado',
  [ESTADOPEDIDO.PREPARANDO]: 'preparando',
  [ESTADOPEDIDO.LISTO]: 'listo',
  [ESTADOPEDIDO.ENCAMINO]: 'en_camino',
  [ESTADOPEDIDO.RECOGIDO]: 'recogido',
  [ESTADOPEDIDO.ENTREGADO]: 'entregado',
  [ESTADOPEDIDO.RECIBIDO]: 'recibido_cliente',
  [ESTADOPEDIDO.RECHAZADO]: 'rechazado',
  [ESTADOPEDIDO.CANCELADO]: 'cancelado',
});
const APIAESTADOPEDIDO = Object.freeze(Object.fromEntries(Object.entries(ESTADOPEDIDOAAPI).map(([cod, txt]) => [txt, cod])));

const METODOPAGOAAPI = Object.freeze({
  [METODOPAGO.EFECTIVO]: 'efectivo',
  [METODOPAGO.TRANSFERENCIA]: 'transferencia',
  [METODOPAGO.TARJETA]: 'tarjeta',
  [METODOPAGO.PAYPAL]: 'paypal',
});
const APIAMETODOPAGO = Object.freeze(Object.fromEntries(Object.entries(METODOPAGOAAPI).map(([cod, txt]) => [txt, cod])));

// Rol que se puede elegir al registrarse (el administrador NUNCA se crea por registro público)
const ROLESREGISTRABLES = Object.freeze(['cliente', 'vendedor', 'repartidor']);

const sinTildes = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

// El campo "vehículo" de la app es texto libre ("Moto", "Bicicleta"...): se traduce al catálogo.
function vehiculoACodigo(texto) {
  const t = sinTildes(texto);
  if (!t) return null;
  if (/moto/.test(t)) return TIPOVEHICULO.MOTOCICLETA;
  if (/camioneta|pickup|furgon/.test(t)) return TIPOVEHICULO.CAMIONETA;
  if (/auto|carro|coche|sedan|taxi/.test(t)) return TIPOVEHICULO.AUTOMOVIL;
  if (/bici/.test(t)) return TIPOVEHICULO.BICICLETA;
  if (/pie|caminando/.test(t)) return TIPOVEHICULO.APIE;
  return null;
}

// La categoría puede llegar como código ('001') o como texto ('Comida'); si no se reconoce -> OTROS
function categoriaACodigo(valor) {
  const t = sinTildes(valor);
  if (/^\d{3}$/.test(t)) return t;
  const porNombre = Object.keys(CATEGORIA).find((k) => sinTildes(k) === t);
  return porNombre ? CATEGORIA[porNombre] : CATEGORIA.OTROS;
}

// Interpreta una categoría escrita por el usuario ('Comida', 'bebida', '001'): { codigo, conocida }
function interpretarCategoria(valor) {
  const crudo = sinTildes(valor);
  if (/^\d{3}$/.test(crudo) && Object.values(CATEGORIA).includes(crudo)) return { codigo: crudo, conocida: true };
  const singular = (t) => sinTildes(t).replace(/s$/, '');
  const clave = Object.keys(CATEGORIA).find((k) => singular(k) === singular(crudo));
  return clave ? { codigo: CATEGORIA[clave], conocida: true } : { codigo: CATEGORIA.OTROS, conocida: false };
}

module.exports = {
  ESTADOPRODUCTOAAPI, APIAESTADOPRODUCTO, APROBACIONAAPI,
  ROLES, TIPOSTELEFONO, TIPOSDIRECCION, TIPODIRECCIONLOCAL, TIPOTELEFONO, TIPODIRECCION, TIPOTELEFONOAAPI, TIPODIRECCIONAAPI, ESTADOPEDIDO, ESTADOPRODUCTO, ESTADOPAGO, APROBACION, METODOPAGO, TIPOVEHICULO,
  CATEGORIA, PROPOSITOCODIGO, ROLAAPI, APIAROL, ROLESREGISTRABLES,
  ESTADOPEDIDOAAPI, APIAESTADOPEDIDO, METODOPAGOAAPI, APIAMETODOPAGO,
  vehiculoACodigo, categoriaACodigo, interpretarCategoria,
};
