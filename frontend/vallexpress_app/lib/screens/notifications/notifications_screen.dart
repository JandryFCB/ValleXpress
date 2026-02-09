import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/pedido_service.dart';
import '../../widgets/gradient_button.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _unreadCount = 0;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndNotifications();
  }

  Future<void> _loadUserRoleAndNotifications() async {
    // Obtener el rol del usuario desde el provider
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.usuario;
    setState(() {
      _userRole = user?['tipoUsuario'] ?? 'cliente';
    });

    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() => _isLoading = true);
      print('🔔 DEBUG FRONTEND - Cargando notificaciones...');

      // Obtener notificaciones reales del backend
      final notificaciones = await PedidoService.obtenerNotificaciones();
      print(
        '🔔 DEBUG FRONTEND - Respuesta del backend: ${notificaciones.length} notificaciones',
      );
      print('🔔 DEBUG FRONTEND - Raw data: $notificaciones');

      // Convertir a formato de UI
      final List<Map<String, dynamic>> notificacionesFormateadas =
          notificaciones.map((n) => _formatearNotificacion(n)).toList();

      setState(() {
        _notifications = notificacionesFormateadas;
        _unreadCount = _notifications
            .where((n) => !(n['leida'] ?? false))
            .length;
        _isLoading = false;
      });

      print(
        '✅ DEBUG FRONTEND - Notificaciones cargadas: ${_notifications.length}',
      );
    } catch (e) {
      print('❌ DEBUG FRONTEND - Error cargando notificaciones: $e');
      setState(() => _isLoading = false);
      // Si hay error, mostrar lista vacía
      _notifications = [];
      _unreadCount = 0;
    }
  }

  Map<String, dynamic> _formatearNotificacion(dynamic notificacion) {
    final tipo = notificacion['tipo'] ?? 'general';
    final leida = notificacion['leida'] ?? false;
    final fecha =
        DateTime.tryParse(notificacion['created_at'] ?? '') ?? DateTime.now();

    // Determinar icono y color según tipo
    IconData icono;
    Color color;
    String titulo = notificacion['titulo'] ?? 'Notificación';

    switch (tipo) {
      case 'pedido_nuevo':
        icono = Icons.shopping_bag;
        color = Colors.orange;
        break;
      case 'pedido_listo':
        icono = Icons.restaurant;
        color = Colors.orange;
        break;
      case 'pedido_en_camino':
        icono = Icons.delivery_dining;
        color = Colors.blue;
        break;
      case 'pedido_entregado':
      case 'pedido_recibido':
        icono = Icons.check_circle;
        color = Colors.green;
        break;
      case 'pedido_cancelado':
        icono = Icons.cancel;
        color = Colors.red;
        break;
      case 'pedido_disponible':
        icono = Icons.local_shipping;
        color = Colors.blue;
        break;
      default:
        icono = Icons.notifications;
        color = AppTheme.primaryColor;
    }

    return {
      'id': notificacion['id']?.toString() ?? '',
      'titulo': titulo,
      'mensaje': notificacion['mensaje'] ?? '',
      'tipo': tipo,
      'leida': leida,
      'fecha': fecha,
      'icono': icono,
      'color': color,
      'pedido_id': notificacion['pedido_id'],
    };
  }

  void _markAsRead(String id) async {
    // Marcar en UI inmediatamente
    setState(() {
      final index = _notifications.indexWhere((n) => n['id'] == id);
      if (index != -1 && !(_notifications[index]['leida'] ?? false)) {
        _notifications[index]['leida'] = true;
        _unreadCount--;
      }
    });

    // Llamar al backend
    try {
      await PedidoService.marcarNotificacionLeida(id);
    } catch (e) {
      // Silenciar error, ya se actualizó la UI
    }
  }

  void _markAllAsRead() {
    setState(() {
      for (var notification in _notifications) {
        notification['leida'] = true;
      }
      _unreadCount = 0;
    });
    _showSuccess('Todas las notificaciones marcadas como leídas');
  }

  void _deleteNotification(String id) {
    setState(() {
      final index = _notifications.indexWhere((n) => n['id'] == id);
      if (index != -1) {
        if (!(_notifications[index]['leida'] ?? false)) {
          _unreadCount--;
        }
        _notifications.removeAt(index);
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    // Debug: mostrar la fecha real para verificar
    print(
      '🔔 DEBUG - Fecha notificación: $date, Diferencia: ${difference.inMinutes} min',
    );

    if (difference.inSeconds < 30) {
      return 'Ahora';
    } else if (difference.inMinutes < 1) {
      return 'Hace ${difference.inSeconds} seg';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} h';
    } else if (difference.inDays < 7) {
      return 'Hace ${difference.inDays} d';
    } else {
      // Formato más legible para fechas antiguas
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      // Si es del año actual, no mostrar el año
      if (date.year == now.year) {
        return '$day/$month $hour:$minute';
      } else {
        return '$day/$month/$year $hour:$minute';
      }
    }
  }

  String _getTituloRol() {
    switch (_userRole) {
      case 'vendedor':
        return 'Notificaciones\nde Ventas';
      case 'repartidor':
        return 'Notificaciones\nde Entregas';
      case 'cliente':
      default:
        return 'Mis\nNotificaciones';
    }
  }

  Color _getRoleColor() {
    switch (_userRole) {
      case 'vendedor':
        return AppTheme.vendedorColor;
      case 'repartidor':
        return AppTheme.repartidorColor;
      case 'cliente':
      default:
        return AppTheme.clienteColor;
    }
  }

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'pedido_nuevo':
        return AppTheme.vendedorColor;
      case 'pedido_listo':
        return AppTheme.vendedorColor;
      case 'pedido_en_camino':
        return AppTheme.repartidorColor;
      case 'pedido_entregado':
      case 'pedido_recibido':
        return AppTheme.successColor;
      case 'pedido_cancelado':
        return AppTheme.errorColor;
      case 'pedido_disponible':
        return AppTheme.repartidorColor;
      case 'nuevo_pedido':
        return AppTheme.vendedorColor;
      case 'repartidor_asignado':
        return AppTheme.repartidorColor;
      case 'pedido_recibido_cliente':
        return AppTheme.clienteColor;
      default:
        return AppTheme.accentColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.notifications,
                color: AppTheme.backgroundColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTituloRol(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  if (_userRole != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getRoleColor().withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getRoleColor().withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _userRole!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _getRoleColor(),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Leer todo'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  backgroundColor: AppTheme.accentColor.withOpacity(0.15),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? _buildEmptyState()
          : _buildNotificationsList(),
    );
  }

  Widget _buildEmptyState() {
    IconData icono;
    String mensaje;
    Color color;

    switch (_userRole) {
      case 'vendedor':
        icono = Icons.store_outlined;
        mensaje = 'No tienes pedidos nuevos';
        color = AppTheme.vendedorColor;
        break;
      case 'repartidor':
        icono = Icons.local_shipping_outlined;
        mensaje = 'No hay pedidos disponibles';
        color = AppTheme.repartidorColor;
        break;
      default:
        icono = Icons.notifications_none_outlined;
        mensaje = 'No tienes notificaciones';
        color = AppTheme.accentColor;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(icono, size: 64, color: color),
          ),
          const SizedBox(height: 32),
          Text(
            mensaje,
            style: TextStyle(
              fontSize: 20,
              color: AppTheme.textPrimaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Las notificaciones aparecerán aquí\nsegún tu actividad',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondaryColor,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          GradientButton(
            text: 'Actualizar',
            onPressed: _loadNotifications,
            icon: Icons.refresh,
            gradientColors: [color, color.withOpacity(0.8)],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList() {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: AppTheme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          final isUnread = !(notification['leida'] ?? false);
          final icono =
              notification['icono'] as IconData? ?? Icons.notifications;
          final color =
              notification['color'] as Color? ?? AppTheme.primaryColor;

          return Dismissible(
            key: Key(notification['id']),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.errorColor, Color(0xFFFF6B6B)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.errorColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: 28,
              ),
            ),
            onDismissed: (_) => _deleteNotification(notification['id']),
            child: GestureDetector(
              onTap: () => _markAsRead(notification['id']),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isUnread
                        ? [AppTheme.cardColor, AppTheme.cardColorLight]
                        : [
                            AppTheme.cardColor.withOpacity(0.8),
                            AppTheme.cardColor.withOpacity(0.6),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isUnread
                        ? color.withOpacity(0.5)
                        : AppTheme.textSecondaryColor.withOpacity(0.2),
                    width: isUnread ? 2 : 1,
                  ),
                  boxShadow: isUnread
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                            spreadRadius: 2,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        // Barra de color lateral para no leídos con gradiente
                        if (isUnread)
                          Container(
                            width: 4,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color, color.withOpacity(0.5)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),

                        // Contenido
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Icono con fondo de color vibrante
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        color.withOpacity(0.3),
                                        color.withOpacity(0.1),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: color.withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(icono, color: color, size: 28),
                                ),
                                const SizedBox(width: 16),

                                // Texto
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              notification['titulo'],
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: isUnread
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                                color: isUnread
                                                    ? AppTheme.textPrimaryColor
                                                    : AppTheme
                                                          .textSecondaryColor,
                                              ),
                                            ),
                                          ),
                                          if (isUnread)
                                            Container(
                                              width: 10,
                                              height: 10,
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    color,
                                                    color.withOpacity(0.7),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: color.withOpacity(
                                                      0.5,
                                                    ),
                                                    blurRadius: 6,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        notification['mensaje'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isUnread
                                              ? AppTheme.textSecondaryColor
                                              : AppTheme.textSecondaryColor
                                                    .withOpacity(0.7),
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 12,
                                            color: isUnread
                                                ? color.withOpacity(0.7)
                                                : AppTheme.textSecondaryColor
                                                      .withOpacity(0.5),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(notification['fecha']),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isUnread
                                                  ? color.withOpacity(0.9)
                                                  : AppTheme.textSecondaryColor
                                                        .withOpacity(0.6),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
