const Notificacion = require('./notificacion.model');




class NotificacionController {
  // Listar notificaciones del usuario (incluye las creadas para ese usuario)
  async listar(req, res) {
    try {
      const usuarioId = req.usuario.id;
      console.log('🔔 DEBUG - Listando notificaciones para usuario:', usuarioId);
      
      const notificaciones = await Notificacion.findAll({
        where: { usuarioId },
        order: [['createdAt', 'DESC']],
      });
      
      console.log('✅ DEBUG - Notificaciones encontradas:', notificaciones.length);
      console.log('📋 DEBUG - Lista:', notificaciones.map(n => ({ id: n.id, titulo: n.titulo, tipo: n.tipo })));
      
      return res.json({ notificaciones });
    } catch (error) {
      console.error('❌ Error listar notificaciones:', error);
      return res.status(500).json({ error: 'Error al obtener notificaciones' });
    }
  }

  // Marcar como leída
  async marcarLeida(req, res) {
    try {
      const { id } = req.params;
      const usuarioId = req.usuario.id;

      console.log('🔔 DEBUG - Marcando notificación como leída:', { id, usuarioId });

      const n = await Notificacion.findByPk(id);
      if (!n) {
        console.log('❌ DEBUG - Notificación no encontrada:', id);
        return res.status(404).json({ error: 'Notificación no encontrada' });
      }
      
      if (n.usuarioId !== usuarioId) {
        console.log('❌ DEBUG - No autorizado. Notificación usuarioId:', n.usuarioId, 'Solicitante:', usuarioId);
        return res.status(403).json({ error: 'No autorizado' });
      }

      await n.update({ leida: true });
      console.log('✅ DEBUG - Notificación marcada como leída:', id);
      
      return res.json({ message: 'Marcada como leída' });
    } catch (error) {
      console.error('❌ Error marcar leida:', error);
      return res.status(500).json({ error: 'Error al actualizar notificación' });
    }
  }
}

module.exports = new NotificacionController();
