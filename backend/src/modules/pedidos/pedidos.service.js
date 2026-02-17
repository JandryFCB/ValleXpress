// backend/src/services/pedidos.service.js
const { Op } = require('sequelize');
const {
  sequelize,
  Pedido,
  DetallePedido,
  Producto,
  Vendedor,
  Notificacion,
} = require('../index');




// Genera un número de pedido simple y único (puedes cambiar formato)
function generarNumeroPedido() {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const rand = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `VX-${yyyy}${mm}${dd}-${rand}`;
}

class StockInsuficienteError extends Error {
  constructor(items) {
    super('Stock insuficiente');
    this.name = 'StockInsuficienteError';
    this.items = items; // [{productoId, disponible, solicitado}]
  }
}

async function crearPedidoConTransaccion({ clienteId, direccionEntregaId, metodoPago, notasCliente, items }) {
  if (!Array.isArray(items) || items.length === 0) {
    const err = new Error('Items del pedido son requeridos');
    err.statusCode = 400;
    throw err;
  }

  // Normaliza items
  const normalizados = items.map(i => ({
    productoId: i.productoId || i.producto_id,
    cantidad: Number(i.cantidad),
    notas: i.notas || null,
  }));

  if (normalizados.some(i => !i.productoId || !Number.isInteger(i.cantidad) || i.cantidad <= 0)) {
    const err = new Error('Items inválidos (productoId y cantidad > 0 requeridos)');
    err.statusCode = 400;
    throw err;
  }

  const productoIds = normalizados.map(i => i.productoId);

  return await sequelize.transaction(async (t) => {
    // 1) Traer productos con BLOQUEO (FOR UPDATE) para evitar carreras
    const productos = await Producto.findAll({
      where: { id: { [Op.in]: productoIds } },
      transaction: t,
      lock: t.LOCK.UPDATE,
    });

    if (productos.length !== productoIds.length) {
      const encontrados = new Set(productos.map(p => p.id));
      const faltantes = productoIds.filter(id => !encontrados.has(id));
      const err = new Error(`Productos no encontrados: ${faltantes.join(', ')}`);
      err.statusCode = 404;
      throw err;
    }

    // 2) Validar que todos los productos sean del MISMO vendedor
    const vendedorIds = new Set(productos.map(p => p.vendedor_id || p.vendedorId));
    if (vendedorIds.size !== 1) {
      const err = new Error('Todos los productos del pedido deben ser del mismo vendedor');
      err.statusCode = 400;
      throw err;
    }
    const vendedorId = [...vendedorIds][0];

    // 3) Validar stock y disponibilidad (ya con lock)
    const porId = new Map(productos.map(p => [p.id, p]));
    const faltantesStock = [];

    for (const item of normalizados) {
      const p = porId.get(item.productoId);
      const stock = Number(p.stock ?? 0);
      const disponible = (p.disponible === undefined) ? true : !!p.disponible;

      if (!disponible || stock < item.cantidad) {
        faltantesStock.push({
          productoId: item.productoId,
          disponible: stock,
          solicitado: item.cantidad,
        });
      }
    }

    if (faltantesStock.length) {
      throw new StockInsuficienteError(faltantesStock);
    }

    // 4) Calcular subtotal y preparar detalles
    let subtotal = 0;
    const detalles = normalizados.map(item => {
      const p = porId.get(item.productoId);
      const precio = Number(p.precio); // numeric(10,2)
      const sub = precio * item.cantidad;
      subtotal += sub;

      return {
        producto_id: p.id,
        cantidad: item.cantidad,
        precio_unitario: precio,
        subtotal: sub,
        notas: item.notas,
      };
    });

    // 5) Traer costo delivery del vendedor (si existe) y calcular total
    const vendedor = await Vendedor.findByPk(vendedorId, { transaction: t });
    const costoDelivery = Number(vendedor?.costo_delivery ?? vendedor?.costoDelivery ?? 0);
    const total = subtotal + costoDelivery;

    // 6) Crear pedido
    const pedido = await Pedido.create({
      numero_pedido: generarNumeroPedido(),
      cliente_id: clienteId,
      vendedor_id: vendedorId,
      repartidor_id: null,
      direccion_entrega_id: direccionEntregaId || null,
      estado: 'pendiente',
      subtotal,
      costo_delivery: costoDelivery,
      total,
      metodo_pago: metodoPago || 'efectivo',
      pagado: false,
      notas_cliente: notasCliente || null,
      fecha_pedido: new Date(),
    }, { transaction: t });

    // 7) Crear detalles
    await DetallePedido.bulkCreate(
      detalles.map(d => ({ ...d, pedido_id: pedido.id })),
      { transaction: t }
    );

    // 8) Descontar stock (todavía dentro de transacción y con lock)
    for (const item of normalizados) {
      const p = porId.get(item.productoId);
      const nuevoStock = Number(p.stock) - item.cantidad;

      await Producto.update(
        { stock: nuevoStock },
        { where: { id: p.id }, transaction: t }
      );
    }

    // 9) Crear notificación para el vendedor (usar usuarioId del vendedor)
    try {
      console.log('🔔 DEBUG - Vendedor encontrado:', {
        vendedorId: vendedor.id,
        usuarioId: vendedor.usuarioId,
        nombreNegocio: vendedor.nombreNegocio
      });
      
      const notificacion = await Notificacion.create({
        usuarioId: vendedor.usuarioId,
        titulo: 'Nuevo pedido recibido',
        mensaje: `Tienes un nuevo pedido #${pedido.numero_pedido} por $${total.toFixed(2)}`,
        tipo: 'pedido_nuevo',
        pedidoId: pedido.id,
        leida: false,
      }, { transaction: t });
      
      console.log('✅ Notificación creada:', notificacion.id);
    } catch (notifError) {
      console.error('❌ Error creando notificación:', notifError);
      // No fallar el pedido si la notificación falla
    }



    // 10) (Opcional) Devolver pedido con detalles
    const pedidoCreado = await Pedido.findByPk(pedido.id, {
      transaction: t,
      include: [{ model: DetallePedido, as: 'detalles', required: false }],
    });

    return pedidoCreado || pedido;

  });
}

module.exports = {
  crearPedidoConTransaccion,
  StockInsuficienteError,
};
