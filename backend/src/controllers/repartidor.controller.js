const Repartidor = require('../models/Repartidor');
const Usuario = require('../models/Usuario');
const Vendedor = require('../models/Vendedor');
const Pedido = require('../models/Pedido');
const Notificacion = require('../models/Notificacion');
const { validationResult } = require('express-validator');


class RepartidorController {
    // Subir foto de perfil del repartidor (base64)
    async subirFotoPerfil(req, res) {
      try {
        const { foto } = req.body;
        if (!foto) {
          return res.status(400).json({ error: 'No se proporcionó foto' });
        }
        const repartidor = await Repartidor.findOne({ where: { usuarioId: req.usuario.id } });
        if (!repartidor) {
          return res.status(404).json({ error: 'Repartidor no encontrado' });
        }
        await repartidor.update({ foto });
        res.json({
          message: 'Foto de perfil actualizada correctamente',
          foto: repartidor.foto
        });
      } catch (error) {
        console.error('Error al subir foto de perfil:', error);
        res.status(500).json({ error: 'Error al subir foto de perfil' });
      }
    }
  // Listar pedidos listos para entrega (no asignados)
  async pedidosPendientes(req, res) {
    try {
      const pedidos = await Pedido.findAll({
        where: {
          estado: 'listo',
          repartidorId: null
        },
        order: [['createdAt', 'DESC']]
      });
      res.json({ pedidos });
    } catch (error) {
      console.error('Error al listar pedidos listos:', error);
      res.status(500).json({ error: 'Error al obtener pedidos listos' });
    }
  }

  // Listar todos los pedidos aceptados por vendedores (para vista del repartidor)
  async pedidosVista(req, res) {
    try {
      const pedidos = await Pedido.findAll({
        where: {
          estado: ['confirmado', 'preparando'] // Excluimos 'listo' porque esos van a pendientes
        },
        include: [
          {
            model: require('../models/Vendedor'),
            as: 'vendedor',
            attributes: ['id', 'nombreNegocio']
          },
          {
            model: require('../models/Usuario'),
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido']
          }
        ],
        order: [['createdAt', 'DESC']]
      });
      res.json({ pedidos });
    } catch (error) {
      console.error('Error al listar pedidos para vista:', error);
      res.status(500).json({ error: 'Error al obtener pedidos para vista' });
    }
  }
  // Crear perfil de repartidor
  async crear(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      // Verificar que el usuario sea tipo repartidor
      if (req.usuario.tipoUsuario !== 'repartidor') {
        return res.status(403).json({ 
          error: 'Solo usuarios tipo repartidor pueden crear este perfil' 
        });
      }

      // Verificar si ya tiene un perfil de repartidor
      const repartidorExistente = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (repartidorExistente) {
        return res.status(409).json({ 
          error: 'Ya tienes un perfil de repartidor registrado' 
        });
      }

      const { vehiculo, placa, licencia } = req.body;

      // Crear repartidor
      const repartidor = await Repartidor.create({
        usuarioId: req.usuario.id,
        vehiculo,
        placa,
        licencia
      });

      res.status(201).json({
        message: 'Perfil de repartidor creado exitosamente',
        repartidor
      });
    } catch (error) {
      console.error('Error al crear repartidor:', error);
      res.status(500).json({ error: 'Error al crear perfil de repartidor' });
    }
  }

  // Obtener todos los repartidores (admin)
  async listar(req, res) {
    try {
      const repartidores = await Repartidor.findAll({
        include: [{
          model: Usuario,
          as: 'usuario',
          attributes: ['id', 'nombre', 'apellido', 'email', 'telefono']
        }],
        order: [['createdAt', 'DESC']]
      });

      res.json({ repartidores });
    } catch (error) {
      console.error('Error al listar repartidores:', error);
      res.status(500).json({ error: 'Error al obtener repartidores' });
    }
  }

  // Obtener mi perfil de repartidor
  async miPerfil(req, res) {
    try {
      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id },
        include: [{
          model: Usuario,
          as: 'usuario',
          attributes: ['id', 'nombre', 'apellido', 'email', 'telefono']
        }]
      });

      if (!repartidor) {
        return res.status(404).json({ 
          error: 'No tienes un perfil de repartidor registrado' 
        });
      }

      res.json({ repartidor });
    } catch (error) {
      console.error('Error al obtener perfil:', error);
      res.status(500).json({ error: 'Error al obtener perfil' });
    }
  }

  // Actualizar perfil
  async actualizar(req, res) {
    try {
      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const { vehiculo, placa, licencia } = req.body;

      await repartidor.update({
        ...(vehiculo && { vehiculo }),
        ...(placa && { placa }),
        ...(licencia && { licencia })
      });

      res.json({
        message: 'Perfil actualizado exitosamente',
        repartidor
      });
    } catch (error) {
      console.error('Error al actualizar repartidor:', error);
      res.status(500).json({ error: 'Error al actualizar perfil' });
    }
  }

  // Cambiar disponibilidad (activar/desactivar)
  async cambiarDisponibilidad(req, res) {
    try {
      const { disponible } = req.body;

      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      await repartidor.update({ disponible });

      res.json({
        message: `Disponibilidad ${disponible ? 'activada' : 'desactivada'} exitosamente`,
        repartidor
      });
    } catch (error) {
      console.error('Error al cambiar disponibilidad:', error);
      res.status(500).json({ error: 'Error al cambiar disponibilidad' });
    }
  }

  // Actualizar ubicación
  async actualizarUbicacion(req, res) {
    try {
      const { latitud, longitud } = req.body;

      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      await repartidor.update({
        ultimaUbicacionLat: latitud,
        ultimaUbicacionLng: longitud
      });

      // Emitir ubicación en tiempo real (WebSocket)
      if (req.io) {
        req.io.emit(`ubicacion_repartidor_${repartidor.id}`, {
          repartidorId: repartidor.id,
          lat: latitud,
          lng: longitud
        });
      }

      res.json({
        message: 'Ubicación actualizada exitosamente',
        ubicacion: { latitud, longitud }
      });
    } catch (error) {
      console.error('Error al actualizar ubicación:', error);
      res.status(500).json({ error: 'Error al actualizar ubicación' });
    }
  }

  // Listar repartidores disponibles
  async listarDisponibles(req, res) {
    try {
      const repartidores = await Repartidor.findAll({
        where: { disponible: true },
        include: [{
          model: Usuario,
          as: 'usuario',
          attributes: ['id', 'nombre', 'apellido', 'telefono']
        }]
      });

      res.json({ repartidores });
    } catch (error) {
      console.error('Error al listar repartidores disponibles:', error);
      res.status(500).json({ error: 'Error al obtener repartidores' });
    }
  }

  // Obtener pedidos asignados al repartidor
  async misPedidos(req, res) {
    try {
      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const pedidos = await Pedido.findAll({
        where: { repartidorId: repartidor.id },
        include: [
          {
            model: require('../models/Vendedor'),
            as: 'vendedor',
            attributes: ['id', 'nombreNegocio', 'latitud', 'longitud']
          },
          {
            model: require('../models/Usuario'),
            as: 'cliente',
            attributes: ['id', 'nombre', 'apellido', 'telefono']
          },
          {
            model: require('../models/Direccion'),
            as: 'direccionEntrega',
            attributes: ['id', 'nombre', 'direccion', 'latitud', 'longitud']
          }

        ],
        order: [['createdAt', 'DESC']]
      });

      // Si un pedido no tiene direccionEntrega, obtener la dirección predeterminada del cliente
      const Direccion = require('../models/Direccion');
      for (let pedido of pedidos) {
        if (!pedido.direccionEntrega) {
          const direccionDefault = await Direccion.findOne({
            where: { 
              usuarioId: pedido.clienteId,
              esPredeterminada: true 
            }
          });
          if (direccionDefault) {
            pedido.dataValues.direccionEntrega = direccionDefault;
          }
        }
      }

      res.json({ pedidos });
    } catch (error) {
      console.error('Error al obtener pedidos:', error);
      res.status(500).json({ error: 'Error al obtener pedidos' });
    }
  }




  // Aceptar pedido y asignar precio de delivery
  async aceptarPedido(req, res) {
    try {
      const { id } = req.params;
      const { costoDelivery } = req.body;

      if (!costoDelivery || costoDelivery <= 0) {
        return res.status(400).json({ error: 'Debes especificar un costo de delivery válido' });
      }

      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const pedido = await Pedido.findByPk(id);

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      // Verificar que el pedido esté listo y no asignado
      if (pedido.estado !== 'listo' || pedido.repartidorId !== null) {
        return res.status(400).json({
          error: 'Este pedido no está disponible para aceptar'
        });
      }

      // Asignar pedido al repartidor y actualizar costo de delivery
      await pedido.update({
        repartidorId: repartidor.id,
        costoDelivery: costoDelivery,
        estado: 'en_camino',
        fechaRecogida: new Date()
      });

      // Emitir evento en tiempo real
      if (req.io) {
        req.io.emit(`pedido_${pedido.id}`, {
          pedidoId: pedido.id,
          estado: pedido.estado,
          repartidorId: repartidor.id
        });
      }

      // Crear y enviar notificación al repartidor
      try {
        const notificacionRepartidor = await Notificacion.create({
          usuarioId: req.usuario.id,
          tipo: 'pedido_aceptado',
          titulo: '¡Pedido aceptado! 🚴',
          mensaje: `Has aceptado el pedido #${pedido.id}. Dirígete a la tienda para recogerlo.`,
          data: { pedidoId: pedido.id, estado: 'en_camino' }
        });
        
        console.log('🔔 DEBUG BACKEND - Notificación creada para repartidor:', notificacionRepartidor.id);
        
        // Emitir notificación en tiempo real al repartidor
        if (req.io) {
          console.log('🔔 DEBUG BACKEND - Emitiendo notificación Socket.IO a repartidor:', req.usuario.id);
          req.io.to(`user:${req.usuario.id}`).emit('notificacion', {
            title: '¡Pedido aceptado! 🚴',
            body: `Has aceptado el pedido #${pedido.id}. Dirígete a la tienda para recogerlo.`,
            data: { 
              tipo: 'pedido_aceptado', 
              pedidoId: pedido.id,
              notificacionId: notificacionRepartidor.id 
            }
          });
        }
      } catch (notifError) {
        console.error('❌ Error al crear notificación para repartidor:', notifError);
        // No fallar el request si la notificación falla
      }

      res.json({
        message: 'Pedido aceptado exitosamente',
        pedido
      });

    } catch (error) {
      console.error('Error al aceptar pedido:', error);
      res.status(500).json({ error: 'Error al aceptar pedido' });
    }
  }

  // Obtener ubicación actual de un repartidor específico
  async obtenerUbicacion(req, res) {
    try {
      const { id } = req.params;

      const repartidor = await Repartidor.findByPk(id, {
        attributes: ['id', 'latitud', 'longitud', 'ultimaUbicacionLat', 'ultimaUbicacionLng']
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      // Usar última ubicación si existe, sino la ubicación guardada
      const lat = repartidor.ultimaUbicacionLat || repartidor.latitud;
      const lng = repartidor.ultimaUbicacionLng || repartidor.longitud;

      if (lat == null || lng == null) {
        return res.status(404).json({ error: 'Ubicación no disponible' });
      }

      res.json({
        repartidorId: repartidor.id,
        lat: lat,
        lng: lng
      });
    } catch (error) {
      console.error('Error al obtener ubicación del repartidor:', error);
      res.status(500).json({ error: 'Error al obtener ubicación' });
    }
  }

  // Actualizar estado del pedido (repartidor)
  async actualizarEstadoPedido(req, res) {
    try {
      const { id } = req.params;
      const { estado } = req.body;

      const repartidor = await Repartidor.findOne({
        where: { usuarioId: req.usuario.id }
      });

      if (!repartidor) {
        return res.status(404).json({ error: 'Repartidor no encontrado' });
      }

      const pedido = await Pedido.findByPk(id);

      if (!pedido) {
        return res.status(404).json({ error: 'Pedido no encontrado' });
      }

      // Verificar que el pedido esté asignado a este repartidor
      if (pedido.repartidorId !== repartidor.id) {
        return res.status(403).json({
          error: 'Este pedido no está asignado a ti'
        });
      }

      // Validar estados permitidos para repartidor
      const estadosPermitidos = ['en_camino', 'entregado'];
      if (!estadosPermitidos.includes(estado)) {
        return res.status(400).json({
          error: 'Estado no válido. Usa: en_camino o entregado'
        });
      }

      const updates = { estado };

      if (estado === 'en_camino') {
        updates.fechaRecogida = new Date();
      } else if (estado === 'entregado') {
        updates.fechaEntrega = new Date();
        // Incrementar pedidos completados
        await repartidor.update({
          pedidosCompletados: repartidor.pedidosCompletados + 1
        });
      }

      await pedido.update(updates);

      // Emitir evento en tiempo real
      if (req.io) {
        req.io.emit(`pedido_${pedido.id}`, {
          pedidoId: pedido.id,
          estado: pedido.estado
        });
      }

      res.json({
        message: 'Estado actualizado exitosamente',
        pedido
      });
    } catch (error) {
      console.error('Error al actualizar estado:', error);
      res.status(500).json({ error: 'Error al actualizar estado' });
    }
  }
}

module.exports = new RepartidorController();
