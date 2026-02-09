/**
 * Seed de datos mock para pruebas E2E de sockets y flujos de pedidos.
 * - Crea (o reutiliza) usuarios: cliente, vendedor, repartidor.
 * - Crea (o reutiliza) un producto del vendedor.
 * - Crea un pedido y lo deja en estado 'en_camino' asignado al repartidor.
 * - Genera y muestra por consola los JWT para cliente y repartidor y el pedidoId.
 *
 * Uso:
 *   cd backend &amp;&amp; node src/scripts/seed_mock_data.js
 *
 * Luego puedes probar sockets con:
 *   node backend/test-socket.js \
 *     --url http://localhost:3000 \
 *     --client-token "<JWT_CLIENTE>" \
 *     --driver-token "<JWT_REPARTIDOR>" \
 *     --pedido-id "<UUID_PEDIDO>"
 */
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const jwt = require('jsonwebtoken');
const fs = require('fs');

const { sequelize } = require('../config/database');
require('../models'); // registra todos los modelos

const Usuario = require('../models/Usuario');
const Vendedor = require('../models/Vendedor');
const Repartidor = require('../models/Repartidor');
const Producto = require('../models/Producto');
const Pedido = require('../models/Pedido');
const DetallePedido = require('../models/DetallePedido');

async function ensureUser({ email, nombre, apellido, tipoUsuario, cedula, telefono = '0000000000', password = 'vallexpress' }) {
  // Busca por email; si no existe, crea
  let user = await Usuario.findOne({ where: { email } });
  if (!user) {
    user = await Usuario.create({
      nombre,
      apellido,
      email,
      telefono,
      cedula,
      passwordHash: password, // será hasheado por hooks
      tipoUsuario,
      activo: true,
      verificado: true,
    });
  }
  return user;
}

async function ensureVendedor(usuario) {
  let vendedor = await Vendedor.findOne({ where: { usuarioId: usuario.id } });
  if (!vendedor) {
    vendedor = await Vendedor.create({
      usuarioId: usuario.id,
      nombreNegocio: `${usuario.nombre} Mock Store`,
      descripcion: 'Negocio de pruebas',
      categoria: 'Mock',
      calificacionPromedio: 0.0,
      totalCalificaciones: 0,
      abiertoAhora: true,
      tiempoPreparacionPromedio: 15,
      costoDelivery: 2.5,
      radioCobertura: 10,
    });
  }
  return vendedor;
}

async function ensureRepartidor(usuario) {
  // Evitar seleccionar la columna "foto" (no existe en schema actual)
  let rep = await Repartidor.findOne({
    where: { usuarioId: usuario.id },
    attributes: { exclude: ['foto'] },
  });
  if (!rep) {
    rep = await Repartidor.create({
      usuarioId: usuario.id,
      vehiculo: 'Moto',
      placa: 'MOCK-000',
      licencia: 'MOCK-LIC-000',
      calificacionPromedio: 5.0,
      totalCalificaciones: 0,
      disponible: true,
      pedidosCompletados: 0,
      latitud: -3.9931,
      longitud: -79.2042,
      cedula: usuario.cedula,
    });
  }
  return rep;
}

async function ensureProducto(vendedor) {
  let prod = await Producto.findOne({ where: { vendedorId: vendedor.id, nombre: 'Hamburguesa Mock' } });
  if (!prod) {
    prod = await Producto.create({
      vendedorId: vendedor.id,
      nombre: 'Hamburguesa Mock',
      descripcion: 'Producto de pruebas',
      precio: 9.99,
      categoria: 'Comida',
      disponible: true,
      tiempoPreparacion: 10,
      stock: 100,
    });
  } else if (Number(prod.stock) < 10) {
    // Asegura stock suficiente para las pruebas
    prod.stock = 100;
    await prod.save();
  }
  return prod;
}

async function createPedidoEnCamino({ cliente, vendedor, repartidor, producto }) {
  // Crea un pedido en 'en_camino' con detalles y asignado
  const cantidad = 2;
  const subtotal = Number(producto.precio) * cantidad;
  const costoDelivery = 2.5;
  const total = subtotal + costoDelivery;

  const pedido = await Pedido.create({
    clienteId: cliente.id,
    vendedorId: vendedor.id,
    repartidorId: repartidor.id,
    subtotal,
    costoDelivery,
    total,
    metodoPago: 'efectivo',
    notasCliente: 'Pedido de prueba',
    estado: 'en_camino',
    fechaRecogida: new Date(),
  });

  await DetallePedido.create({
    pedidoId: pedido.id,
    productoId: producto.id,
    cantidad,
    precioUnitario: producto.precio,
    subtotal,
  });

  // Ajuste de stock básico (simula descuento)
  producto.stock = Math.max(0, Number(producto.stock) - cantidad);
  await producto.save();

  return pedido;
}

async function main() {
  try {
    await sequelize.authenticate();

    // Alinear schema en caliente: asegurar columna 'foto' esperada por el modelo Repartidor
    await sequelize.query('ALTER TABLE IF EXISTS "repartidores" ADD COLUMN IF NOT EXISTS "foto" TEXT;');

    // No hacemos sync alter aquí para no tocar estructura; asumimos migrado/sync por server.js
    // await sequelize.sync({ alter: false });

    // Usuarios mock
    const cliente = await ensureUser({
      email: 'mock.cliente@vallexpress.local',
      nombre: 'Cliente',
      apellido: 'Mock',
      tipoUsuario: 'cliente',
      cedula: '1111111111',
    });

    const vendedorUser = await ensureUser({
      email: 'mock.vendedor@vallexpress.local',
      nombre: 'Vendedor',
      apellido: 'Mock',
      tipoUsuario: 'vendedor',
      cedula: '2222222222',
    });

    const repartidorUser = await ensureUser({
      email: 'mock.repartidor@vallexpress.local',
      nombre: 'Repartidor',
      apellido: 'Mock',
      tipoUsuario: 'repartidor',
      cedula: '3333333333',
    });

    // Perfiles vendedor/repartidor
    const vendedor = await ensureVendedor(vendedorUser);
    const repartidor = await ensureRepartidor(repartidorUser);

    // Producto
    const producto = await ensureProducto(vendedor);

    // Pedido en_camino asignado al repartidor
    const pedido = await createPedidoEnCamino({ cliente, vendedor, repartidor, producto });

    // Tokens
    const secret = process.env.JWT_SECRET || 'devsecret';
    const clientToken = jwt.sign(
      { id: cliente.id, email: cliente.email, tipoUsuario: 'cliente', cedula: cliente.cedula },
      secret,
      { expiresIn: '30d' }
    );
    const driverToken = jwt.sign(
      { id: repartidorUser.id, email: repartidorUser.email, tipoUsuario: 'repartidor', cedula: repartidorUser.cedula },
      secret,
      { expiresIn: '30d' }
    );

    console.log('========================================');
    console.log('✅ Seed mock completado');
    console.log('Cliente: ', cliente.email);
    console.log('Repartidor: ', repartidorUser.email);
    console.log('Vendedor: ', vendedorUser.email);
    console.log('Producto: ', producto.nombre, '($' + producto.precio + ')');
    console.log('Pedido en_camino: ', pedido.id);
    console.log('----------------------------------------');
    console.log('CLIENT_TOKEN=', clientToken);
    console.log('DRIVER_TOKEN =', driverToken);
    console.log('PEDIDO_ID    =', pedido.id);
    console.log('----------------------------------------');
    console.log('Ejecuta test de sockets:');
    console.log('  node backend/test-socket.js \\');
    console.log('    --url http://localhost:3000 \\');
    console.log('    --client-token "' + clientToken + '" \\');
    console.log('    --driver-token "' + driverToken + '" \\');
    console.log('    --pedido-id "' + pedido.id + '"');
    console.log('========================================');

    // Escribir tokens y pedido en archivo para uso automatizado
    try {
      const outDir = path.join(__dirname, '../../tmp');
      fs.mkdirSync(outDir, { recursive: true });
      const outPath = path.join(outDir, 'socket-test.json');
      fs.writeFileSync(outPath, JSON.stringify({
        url: 'http://localhost:3000',
        clientToken,
        driverToken,
        pedidoId: pedido.id,
      }, null, 2));
      console.log('📝 Archivo generado:', outPath);
    } catch (err) {
      console.warn('No se pudo escribir archivo de tokens:', err.message || err);
    }

    process.exit(0);
  } catch (e) {
    console.error('❌ Seed mock error:', e);
    process.exit(1);
  }
}

main();
