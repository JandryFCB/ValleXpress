/* controllers/pedido.controller.js */

const Pedido = require('../models/Pedido');
const Usuario = require('../models/Usuario');
const Vendedor = require('../models/Vendedor');
const Repartidor = require('../models/Repartidor');
const Notificacion = require('../models/Notificacion');
const DetallePedido = require('../models/DetallePedido');
const Producto = require('../models/Producto');
const Direccion = require('../models/Direccion');
const { sequelize } = require('../config/database');


class PedidoController {
  async obtenerPorId(req, res) {
    try {
      const { id } = req.params;

      const pedido = await Pedido.findByPk(id, {
        include: [
          {
            model: Usuario,
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
          },
          {
            model: Vendedor,
            as: 'vendedor',
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Repartidor,
            as: 'repartidor',
            required: false,
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Direccion,
            as: 'direccionEntrega',
            required: false,
          },
          {
            model: DetallePedido,
            as: 'detalles',
            include: [
              {
                model: Producto,
                as: 'producto',
              },
            ],
          },
        ],
      });


      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      res.json(pedido);
    } catch (error) {
      console.error('❌ Error obtener pedido por ID:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async crear(req, res) {
    const t = await sequelize.transaction();
    try {
      const { vendedorId, productos, metodoPago, notasCliente, direccionEntregaId } = req.body;
      const clienteId = req.usuario.id;

      console.log('🔔 DEBUG BACKEND - Creando pedido:', { clienteId, vendedorId, productosCount: productos?.length });

      // 1) Validar stock con lock y calcular subtotal
      let subtotal = 0;
      const afectaciones = []; // { producto, cantidad }

      for (const item of productos) {
        const producto = await Producto.findByPk(item.productoId, {
          transaction: t,
          lock: true,
        });
        if (!producto) {
          await t.rollback();
          return res.status(404).json({ error: `Producto ${item.productoId} no encontrado` });
        }
        const cant = Number(item.cantidad) || 0;
        if (producto.stock < cant) {
          await t.rollback();
          return res.status(400).json({
            error: `Stock insuficiente para ${producto.nombre}`,
            disponible: producto.stock,
            solicitado: cant,
            productoId: producto.id,
            code: 'STOCK_INSUFICIENTE',
          });
        }
        subtotal += Number(producto.precio) * cant;
        afectaciones.push({ producto, cantidad: cant });
      }

      // 2) Crear pedido
      const pedido = await Pedido.create({
        clienteId,
        vendedorId,
        direccionEntregaId: direccionEntregaId || null,
        subtotal,
        costoDelivery: 0, // se asignará cuando el repartidor acepte
        total: subtotal,
        metodoPago,
        notasCliente,
      }, { transaction: t });


      console.log('🔔 DEBUG BACKEND - Pedido creado:', pedido.id);

      // 3) Crear detalles y descontar stock
      for (const item of productos) {
        const producto = await Producto.findByPk(item.productoId, {
          transaction: t,
          lock: true,
        });
        const cant = Number(item.cantidad) || 0;

        await DetallePedido.create({
          pedidoId: pedido.id,
          productoId: producto.id,
          cantidad: cant,
          precioUnitario: producto.precio,
          subtotal: Number(producto.precio) * cant,
        }, { transaction: t });
      }

      // Descontar stock y desactivar si llega a 0
      for (const { producto, cantidad } of afectaciones) {
        const nuevoStock = Number(producto.stock) - Number(cantidad);
        producto.stock = nuevoStock;
        if (nuevoStock <= 0) {
          producto.disponible = false;
        }
        await producto.save({ transaction: t });
      }

      await t.commit();
      
      // NOTIFICAR AL VENDEDOR: Nuevo pedido recibido (después del commit)
      try {
        console.log('🔔 DEBUG BACKEND - Buscando vendedor con ID:', vendedorId);
        const vendedor = await Vendedor.findByPk(vendedorId);
        console.log('🔔 DEBUG BACKEND - Vendedor encontrado:', vendedor ? 'SÍ' : 'NO');
        
        if (vendedor) {
          console.log('🔔 DEBUG BACKEND - vendedor.usuarioId:', vendedor.usuarioId);
          console.log('🔔 DEBUG BACKEND - vendedor.id:', vendedor.id);
          
          const notifCreada = await Notificacion.create({
            usuarioId: vendedor.usuarioId,
            titulo: '¡Nuevo pedido recibido! 🛒',
            mensaje: `Tienes un nuevo pedido #${pedido.id.toString().substring(0, 8)}`,
            tipo: 'pedido_nuevo',
            pedidoId: pedido.id,
          });
          console.log('✅ DEBUG BACKEND - Notificación creada:', notifCreada.id);

          if (req.io) {
            console.log('🔔 DEBUG BACKEND - Emitiendo Socket.IO a user:', vendedor.usuarioId);
            req.io.to(`user:${vendedor.usuarioId}`).emit('notificacion', {
              title: '¡Nuevo pedido recibido! 🛒',
              message: `Tienes un nuevo pedido`,
              tipo: 'pedido_nuevo',
              pedidoId: pedido.id,
              ts: Date.now(),
            });
          }
        } else {
          console.log('❌ DEBUG BACKEND - No se encontró vendedor con ID:', vendedorId);
        }
      } catch (e) {
        console.error('❌ DEBUG BACKEND - Error creando notificación:', e);
        console.error('❌ DEBUG BACKEND - Stack:', e.stack);
      }

      // Emitir notificación en tiempo real al cliente
      try {
        if (req.io) {
          req.io.to(`user:${clienteId}`).emit('notificacion', {
            title: 'Pedido creado',
            message: `Tu pedido fue creado exitosamente`,
            tipo: 'pedido_creado',
            pedidoId: pedido.id,
            estado: 'pendiente',
            ts: Date.now(),
          });
        }
      } catch (e) {
        console.error('Error emitiendo notificación de pedido creado:', e);
      }

      return res.status(201).json({ pedido });

    } catch (error) {

      await t.rollback();
      console.error('❌ Error crear pedido:', error);
      return res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async misPedidos(req, res) {
    try {
      const clienteId = req.usuario.id;

      const pedidos = await Pedido.findAll({
        where: { clienteId },
        include: [
          {
            model: Vendedor,
            as: 'vendedor',
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Repartidor,
            as: 'repartidor',
            required: false,
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Direccion,
            as: 'direccionEntrega',
            required: false,
          },
          {
            model: DetallePedido,
            as: 'detalles',
            include: [
              {
                model: Producto,
                as: 'producto',
              },
            ],
          },
        ],
        order: [['fechaPedido', 'DESC']],
      });


      res.json(pedidos);
    } catch (error) {
      console.error('❌ Error obtener mis pedidos:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async pedidosVendedor(req, res) {
    try {
      const usuarioId = req.usuario.id;

      const vendedor = await Vendedor.findOne({
        where: { usuarioId },
        attributes: ['id'],
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      const pedidos = await Pedido.findAll({
        where: { vendedorId: vendedor.id },
        include: [
          {
            model: Usuario,
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
          },
          {
            model: Repartidor,
            as: 'repartidor',
            required: false,
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Direccion,
            as: 'direccionEntrega',
            required: false,
          },
          {
            model: DetallePedido,
            as: 'detalles',
            include: [
              {
                model: Producto,
                as: 'producto',
              },
            ],
          },
        ],
        order: [['fechaPedido', 'DESC']],
      });


      res.json(pedidos);
    } catch (error) {
      console.error('❌ Error obtener pedidos vendedor:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async actualizarEstado(req, res) {
    try {
      const { id } = req.params;
      const { estado } = req.body;
      const usuarioId = req.usuario.id;

      const vendedor = await Vendedor.findOne({
        where: { usuarioId },
        attributes: ['id'],
      });

      if (!vendedor) {
        return res.status(404).json({ error: 'Vendedor no encontrado' });
      }

      const pedido = await Pedido.findOne({
        where: { id, vendedorId: vendedor.id },
      });

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      const fechaCampo = {
        confirmado: 'fechaConfirmacion',
        preparando: 'fechaPreparacion',
        listo: 'fechaListo',
      }[estado];

      await pedido.update({
        estado,
        [fechaCampo]: new Date(),
      });

      // Emitir y persistir notificaciones cuando el pedido está listo
      try {
        console.log('🔔 DEBUG BACKEND - actualizarEstado:', { estado, pedidoId: pedido.id, clienteId: pedido.clienteId, tieneIo: !!req.io });
        
        if (estado === 'listo') {
          console.log('🔔 DEBUG BACKEND - Pedido marcado como listo, enviando notificaciones...');
          const shortMsg = `Pedido listo: ${pedido.id}`;
          
          // 1) Notificar al CLIENTE que su pedido está listo
          try {
            console.log('🔔 DEBUG BACKEND - Creando notificación para cliente:', pedido.clienteId);
            const notifCliente = await Notificacion.create({
              usuarioId: pedido.clienteId,
              titulo: '¡Tu pedido está listo! 🍽️',
              mensaje: `Tu pedido #${pedido.id.toString().substring(0, 8)} está listo y pronto será asignado a un repartidor`,
              tipo: 'pedido_listo',
              pedidoId: pedido.id,
            });
            console.log('✅ DEBUG BACKEND - Notificación cliente creada:', notifCliente.id);
          } catch (e) {
            console.error('❌ DEBUG BACKEND - Error notificación cliente:', e.message);
          }
          
          // Emitir Socket.IO al cliente
          if (req.io) {
            try {
              console.log('🔔 DEBUG BACKEND - Emitiendo Socket.IO a cliente:', pedido.clienteId);
              req.io.to(`user:${pedido.clienteId}`).emit('notificacion', {
                title: '¡Tu pedido está listo! 🍽️',
                message: `Tu pedido está listo y pronto será asignado a un repartidor`,
                tipo: 'pedido_listo',
                pedidoId: pedido.id,
                ts: Date.now(),
              });
            } catch (e) {
              console.error('❌ DEBUG BACKEND - Error Socket.IO cliente:', e.message);
            }
          } else {
            console.log('⚠️ DEBUG BACKEND - req.io no disponible para notificación cliente');
          }
          
          // 2) Notificar a REPARTIDORES disponibles
          try {
            const repartidores = await Repartidor.findAll({ where: { disponible: true } });
            console.log('🔔 DEBUG BACKEND - Repartidores disponibles encontrados:', repartidores.length);
            
            for (const rep of repartidores) {
              const usuarioDest = rep.usuarioId;
              if (!usuarioDest) {
                console.log('⚠️ DEBUG BACKEND - Repartidor sin usuarioId:', rep.id);
                continue;
              }
              
              try {
                const notifRepartidor = await Notificacion.create({
                  usuarioId: usuarioDest,
                  titulo: 'Pedido listo',
                  mensaje: shortMsg,
                  tipo: 'pedido_listo',
                  pedidoId: pedido.id,
                });
                console.log('✅ DEBUG BACKEND - Notificación repartidor creada:', notifRepartidor.id, 'para usuario:', usuarioDest);
              } catch (e) {
                console.error('❌ DEBUG BACKEND - Error notificación repartidor:', usuarioDest, e.message);
              }

              if (req.io) {
                try {
                  req.io.to(`user:${usuarioDest}`).emit('notificacion', {
                    title: 'Pedido listo',
                    message: shortMsg,
                    tipo: 'pedido_listo',
                    pedidoId: pedido.id,
                    vendedorId: pedido.vendedorId,
                    ts: Date.now(),
                  });
                } catch (e) {
                  console.error('❌ DEBUG BACKEND - Error Socket.IO repartidor:', usuarioDest, e.message);
                }
              }
            }
          } catch (e) {
            console.error('❌ DEBUG BACKEND - Error buscando repartidores:', e.message);
          }
        } else {
          console.log('🔔 DEBUG BACKEND - Estado no es listo, no se envían notificaciones. Estado:', estado);
        }
      } catch (err) {
        console.error('❌ DEBUG BACKEND - Error general en notificaciones:', err);
      }



      res.json(pedido);
    } catch (error) {
      console.error('❌ Error actualizar estado:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async cancelar(req, res) {
    const t = await sequelize.transaction();
    try {
      const { id } = req.params;
      const clienteId = req.usuario.id;

      const pedido = await Pedido.findOne({
        where: { id, clienteId },
        transaction: t,
        lock: true,
      });

      if (!pedido) {
        await t.rollback();
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      if (pedido.estado !== 'pendiente') {
        await t.rollback();
        return res.status(400).json({ error: 'No se puede cancelar un pedido que ya está en proceso' });
      }

      // Traer detalles del pedido
      const detalles = await DetallePedido.findAll({
        where: { pedidoId: pedido.id },
        transaction: t,
        lock: true,
      });

      // Reponer stock por cada detalle
      for (const d of detalles) {
        const producto = await Producto.findByPk(d.productoId, {
          transaction: t,
          lock: true,
        });
        if (!producto) continue;

        const nuevoStock = Number(producto.stock) + Number(d.cantidad);
        producto.stock = nuevoStock;
        // Si estaba en 0 y vuelve a >0, activar automáticamente
        if (nuevoStock > 0) {
          producto.disponible = true;
        }
        await producto.save({ transaction: t });
      }

      // Cambiar estado del pedido
      await pedido.update({ estado: 'cancelado' }, { transaction: t });

      // Notificar al VENDEDOR que el pedido fue cancelado
      try {
        const vendedor = await Vendedor.findByPk(pedido.vendedorId);
        if (vendedor) {
          // Buscar notificación existente de nuevo pedido y actualizarla
          const notifExistente = await Notificacion.findOne({
            where: {
              usuarioId: vendedor.usuarioId,
              pedidoId: pedido.id,
              tipo: 'pedido_nuevo'
            }
          });
          
          if (notifExistente) {
            await notifExistente.update({
              titulo: 'Pedido cancelado',
              mensaje: `El pedido #${pedido.id.toString().substring(0, 8)} fue cancelado por el cliente`,
              tipo: 'pedido_cancelado',
              leida: false
            });
          } else {
            await Notificacion.create({
              usuarioId: vendedor.usuarioId,
              titulo: 'Pedido cancelado',
              mensaje: `El pedido #${pedido.id.toString().substring(0, 8)} fue cancelado por el cliente`,
              tipo: 'pedido_cancelado',
              pedidoId: pedido.id,
            });
          }

          if (req.io) {
            req.io.to(`user:${vendedor.usuarioId}`).emit('notificacion', {
              title: 'Pedido cancelado',
              message: `El pedido fue cancelado por el cliente`,
              tipo: 'pedido_cancelado',
              pedidoId: pedido.id,
              estado: 'cancelado',
              ts: Date.now(),
            });
          }
        }
      } catch (e) {
        console.error('Error notificando cancelación al vendedor:', e);
      }

      await t.commit();

      return res.json({ message: 'Pedido cancelado exitosamente' });
    } catch (error) {

      await t.rollback();
      console.error('❌ Error cancelar pedido:', error);
      return res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async marcarEnCamino(req, res) {
    try {
      const { id } = req.params;
      const usuarioId = req.usuario.id;

      const repartidor = await Repartidor.findOne({
        where: { usuarioId },
        attributes: ['id'],
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const pedido = await Pedido.findOne({
        where: { id, repartidorId: repartidor.id },
      });

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      if (pedido.estado !== 'listo') {
        return res.status(400).json({ error: 'El pedido debe estar listo para marcar en camino' });
      }

      await pedido.update({
        estado: 'en_camino',
        fechaRecogida: new Date(),
      });

      // Notificar al cliente que su pedido está en camino
      try {
        await Notificacion.create({
          usuarioId: pedido.clienteId,
          titulo: '¡Tu pedido está en camino! 🚴',
          mensaje: `El repartidor va en camino con tu pedido #${pedido.id.toString().substring(0, 8)}`,
          tipo: 'pedido_en_camino',
          pedidoId: pedido.id,
        });
      } catch (e) {
        console.error('Error creando notificación en camino:', e);
      }

      // Emitir notificación en tiempo real al cliente
      try {
        if (req.io) {
          req.io.to(`user:${pedido.clienteId}`).emit('notificacion', {
            title: '¡Tu pedido está en camino! 🚴',
            message: `El repartidor va en camino con tu pedido`,
            tipo: 'pedido_en_camino',
            pedidoId: pedido.id,
            estado: 'en_camino',
            ts: Date.now(),
          });
        }
      } catch (e) {
        console.error('Error emitiendo notificación en camino:', e);
      }

      res.json({ message: 'Pedido marcado como en camino' });
    } catch (error) {

      console.error('❌ Error marcar en camino:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async marcarRecogido(req, res) {
    try {
      const { id } = req.params;
      const usuarioId = req.usuario.id;

      console.log('🔔 DEBUG marcarRecogido - Iniciando:', { pedidoId: id, usuarioId });

      const repartidor = await Repartidor.findOne({
        where: { usuarioId },
        attributes: ['id'],
      });

      if (!repartidor) {
        console.log('❌ DEBUG marcarRecogido - Repartidor no encontrado');
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      console.log('✅ DEBUG marcarRecogido - Repartidor:', repartidor.id);

      const pedido = await Pedido.findOne({
        where: { id, repartidorId: repartidor.id },
        include: [
          {
            model: Usuario,
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
          },
          {
            model: Vendedor,
            as: 'vendedor',
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
        ],
      });

      if (!pedido) {
        console.log('❌ DEBUG marcarRecogido - Pedido no encontrado');
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      console.log('✅ DEBUG marcarRecogido - Pedido encontrado:', { 
        id: pedido.id, 
        estado: pedido.estado,
        numeroPedido: pedido.numeroPedido,
        clienteId: pedido.clienteId 
      });

      // Permitir marcar como recogido si está 'listo' o 'en_camino'
      if (pedido.estado !== 'listo' && pedido.estado !== 'en_camino') {
        console.log('❌ DEBUG marcarRecogido - Estado inválido:', pedido.estado);
        return res.status(400).json({ error: 'El pedido debe estar listo o en camino para marcar como recogido' });
      }

      await pedido.update({
        estado: 'recogido',
        fechaRecogida: new Date(),
      });

      console.log('✅ DEBUG marcarRecogido - Pedido actualizado a recogido');

      // Crear notificación para el cliente
      try {
        const pedidoIdStr = pedido.id ? pedido.id.toString() : '';
        const numeroMostrar = pedido.numeroPedido || pedidoIdStr.substring(0, 8);
        
        console.log('🔔 DEBUG marcarRecogido - Creando notificación:', {
          usuarioId: pedido.clienteId,
          numeroMostrar: numeroMostrar
        });

        await Notificacion.create({
          usuarioId: pedido.clienteId,
          titulo: '¡Tu pedido fue recogido! 🚴',
          mensaje: `El repartidor recogió tu pedido #${numeroMostrar} y va en camino`,
          tipo: 'pedido_recogido',
          pedidoId: pedido.id,
        });
        
        console.log('✅ DEBUG marcarRecogido - Notificación creada');
      } catch (e) {
        console.error('❌ DEBUG marcarRecogido - Error creando notificación:', e);
        console.error('❌ Stack:', e.stack);
      }

      // Emitir notificación en tiempo real si hay socket
      try {
        if (req.io) {
          console.log('🔔 DEBUG marcarRecogido - Emitiendo Socket.IO a:', pedido.clienteId);
          req.io.to(`user:${pedido.clienteId}`).emit('notificacion', {
            title: '¡Tu pedido fue recogido! 🚴',
            message: `El repartidor recogió tu pedido y va en camino`,
            tipo: 'pedido_recogido',
            pedidoId: pedido.id,
            estado: 'recogido',
            ts: Date.now(),
          });
          console.log('✅ DEBUG marcarRecogido - Socket.IO emitido');
        } else {
          console.log('⚠️ DEBUG marcarRecogido - req.io no disponible');
        }
      } catch (e) {
        console.error('❌ DEBUG marcarRecogido - Error emitiendo notificación:', e);
      }

      res.json({ 
        message: 'Pedido marcado como recogido',
        pedido: {
          id: pedido.id,
          estado: 'recogido',
          fechaRecogida: new Date(),
        }
      });
    } catch (error) {
      console.error('❌ Error marcar recogido:', error);
      console.error('❌ Stack completo:', error.stack);
      res.status(500).json({ error: 'Error interno del servidor', detalle: error.message });
    }
  }


  async marcarEntregado(req, res) {

    try {
      const { id } = req.params;
      const usuarioId = req.usuario.id;

      const repartidor = await Repartidor.findOne({
        where: { usuarioId },
        attributes: ['id'],
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const pedido = await Pedido.findOne({
        where: { id, repartidorId: repartidor.id },
      });

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      if (pedido.estado !== 'recogido') {
        return res.status(400).json({ error: 'El pedido debe estar recogido para marcar entregado' });
      }


      await pedido.update({
        estado: 'entregado',
        fechaEntrega: new Date(),
      });

      // Notificar al cliente que su pedido fue entregado
      try {
        await Notificacion.create({
          usuarioId: pedido.clienteId,
          titulo: '¡Pedido entregado! 🎉',
          mensaje: `Tu pedido #${pedido.id.toString().substring(0, 8)} fue entregado. Por favor confirma la recepción.`,
          tipo: 'pedido_entregado',
          pedidoId: pedido.id,
        });
      } catch (e) {
        console.error('Error creando notificación entregado:', e);
      }

      // Emitir notificación en tiempo real al cliente
      try {
        if (req.io) {
          req.io.to(`user:${pedido.clienteId}`).emit('notificacion', {
            title: '¡Pedido entregado! 🎉',
            message: `Tu pedido fue entregado. Por favor confirma la recepción.`,
            tipo: 'pedido_entregado',
            pedidoId: pedido.id,
            estado: 'entregado',
            ts: Date.now(),
          });
        }
      } catch (e) {
        console.error('Error emitiendo notificación entregado:', e);
      }

      res.json({ message: 'Pedido marcado como entregado' });
    } catch (error) {

      console.error('❌ Error marcar entregado:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async marcarRecibidoCliente(req, res) {
    try {
      const { id } = req.params;
      const clienteId = req.usuario.id;

      const pedido = await Pedido.findOne({
        where: { id, clienteId },
      });

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      if (pedido.estado !== 'entregado') {
        return res.status(400).json({ error: 'El pedido debe estar entregado para marcar recibido' });
      }

      await pedido.update({ estado: 'recibido_cliente' });

      // Notificar al VENDEDOR y REPARTIDOR que el cliente recibió el pedido
      try {
        // Notificar al VENDEDOR
        const vendedor = await Vendedor.findByPk(pedido.vendedorId);
        if (vendedor) {
          await Notificacion.create({
            usuarioId: vendedor.usuarioId,
            titulo: '¡Pedido recibido por el cliente! ✅',
            mensaje: `El cliente recibió el pedido #${pedido.id.toString().substring(0, 8)}`,
            tipo: 'pedido_recibido_cliente',
            pedidoId: pedido.id,
          });

          if (req.io) {
            req.io.to(`user:${vendedor.usuarioId}`).emit('notificacion', {
              title: '¡Pedido recibido por el cliente! ✅',
              message: `El cliente recibió el pedido`,
              tipo: 'pedido_recibido_cliente',
              pedidoId: pedido.id,
              ts: Date.now(),
            });
          }
        }

        // Notificar al REPARTIDOR (si hay uno asignado)
        if (pedido.repartidorId) {
          const repartidor = await Repartidor.findByPk(pedido.repartidorId);
          if (repartidor) {
            await Notificacion.create({
              usuarioId: repartidor.usuarioId,
              titulo: '¡Pedido recibido por el cliente! ✅',
              mensaje: `El cliente recibió el pedido #${pedido.id.toString().substring(0, 8)}`,
              tipo: 'pedido_recibido_cliente',
              pedidoId: pedido.id,
            });

            if (req.io) {
              req.io.to(`user:${repartidor.usuarioId}`).emit('notificacion', {
                title: '¡Pedido recibido por el cliente! ✅',
                message: `El cliente recibió el pedido`,
                tipo: 'pedido_recibido_cliente',
                pedidoId: pedido.id,
                ts: Date.now(),
              });
            }
          }
        }
      } catch (e) {
        console.error('Error notificando pedido recibido por cliente:', e);
      }

      // devolver pedido actualizado para el frontend
      const pedidoActualizado = await Pedido.findByPk(pedido.id, {
        include: [
          {
            model: Usuario,
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
          },
          {
            model: Vendedor,
            as: 'vendedor',
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Repartidor,
            as: 'repartidor',
            required: false,
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: DetallePedido,
            as: 'detalles',
            include: [{ model: Producto, as: 'producto' }],
          },
        ],
      });

      res.json({ pedido: pedidoActualizado });
    } catch (error) {
      console.error('❌ Error marcar recibido cliente:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }

  async aceptarRepartidor(req, res) {
    try {
      const { id } = req.params;
      const { costoDelivery } = req.body;
      const usuarioId = req.usuario.id;

      const repartidor = await Repartidor.findOne({
        where: { usuarioId },
        attributes: ['id'],
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const repartidorId = repartidor.id;

      const pedido = await Pedido.findByPk(id);

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      if (pedido.repartidorId) {
        return res.status(400).json({ error: 'El pedido ya tiene un repartidor asignado' });
      }

      if (pedido.estado !== 'listo') {
        return res.status(400).json({ error: 'El pedido debe estar listo para asignar repartidor' });
      }

      const costoNum = Number(costoDelivery);
      const subtotalNum = Number(pedido.subtotal);
      if (!Number.isFinite(costoNum) || costoNum < 0) {
        return res.status(400).json({ error: 'Costo de delivery inválido' });
      }
      const totalNum = subtotalNum + costoNum;

      await pedido.update({
        repartidorId,
        costoDelivery: costoNum,
        total: totalNum,
        estado: 'en_camino',
        fechaRecogida: new Date(),
      });

      // Notificar al CLIENTE que un repartidor aceptó su pedido
      try {
        await Notificacion.create({
          usuarioId: pedido.clienteId,
          titulo: '¡Repartidor asignado! 🚴',
          mensaje: `Un repartidor aceptó tu pedido #${pedido.id.toString().substring(0, 8)} y va en camino`,
          tipo: 'pedido_en_camino',
          pedidoId: pedido.id,
        });
      } catch (e) {
        console.error('Error creando notificación de repartidor asignado:', e);
      }

      // Emitir notificación en tiempo real al cliente
      try {
        if (req.io) {
          req.io.to(`user:${pedido.clienteId}`).emit('notificacion', {
            title: '¡Repartidor asignado! 🚴',
            message: `Un repartidor aceptó tu pedido y va en camino`,
            tipo: 'pedido_en_camino',
            pedidoId: pedido.id,
            estado: 'en_camino',
            repartidorId: repartidorId,
            ts: Date.now(),
          });
        }
      } catch (e) {
        console.error('Error emitiendo notificación de repartidor asignado:', e);
      }

      // devolver pedido actualizado para el frontend
      const pedidoActualizado = await Pedido.findByPk(pedido.id, {
        include: [
          {
            model: Usuario,
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
          },
          {
            model: Vendedor,
            as: 'vendedor',
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: Repartidor,
            as: 'repartidor',
            required: false,
            include: [
              {
                model: Usuario,
                as: 'usuario',
                attributes: ['id', 'nombre', 'apellido', 'telefono', 'email'],
              },
            ],
          },
          {
            model: DetallePedido,
            as: 'detalles',
            include: [{ model: Producto, as: 'producto' }],
          },
        ],
      });

      res.json({ pedido: pedidoActualizado });
    } catch (error) {
      console.error('❌ Error aceptar repartidor:', error);
      res.status(500).json({ error: 'Error interno del servidor' });
    }
  }
}

module.exports = new PedidoController();
