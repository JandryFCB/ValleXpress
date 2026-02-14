import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:vallexpress_app/providers/auth_provider.dart';

import 'package:vallexpress_app/screens/vendedor/mis_productos_screen.dart';
import 'package:vallexpress_app/screens/vendedor/agregar_producto_screen.dart';
import 'package:vallexpress_app/screens/vendedor/vendedor_mis_pedidos_screen.dart';
import 'package:vallexpress_app/screens/cliente/cliente_mis_pedidos_screen.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';

import '../profile/cliente_profile_screen.dart';
import '../profile/vendedor_profile_screen.dart';
import '../profile/repartidor_profile_screen.dart';
import '../profile/settings_screen.dart';
import 'package:vallexpress_app/screens/cliente/cliente_productos_screen.dart';
import 'package:vallexpress_app/screens/repartidor/repartidor_pedidos_screen.dart';
import 'package:vallexpress_app/screens/repartidor/repartidor_rutas_screen.dart';

import '../../providers/pedidos_provider.dart';
import 'package:vallexpress_app/screens/cliente/rastrear_pedido_screen.dart';
import 'package:vallexpress_app/screens/notifications/notifications_screen.dart';
import 'dart:async';
import '../../services/socket_tracking_service.dart';
import '../../services/pedido_service.dart';
import '../../services/repartidor_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TrackingSocketService _homeSocket = TrackingSocketService();
  StreamSubscription<Map<String, dynamic>>? _homeSub;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  LatLng? _driverLatLngHome;
  String? _joinedPedidoId;
  DateTime? _lastPedidosFetch;
  Map<String, dynamic>? _activePedidoCache;
  List<Map<String, dynamic>> _pedidosActivosList =
      []; // Lista de pedidos activos
  int _currentPedidoIndex = 0; // Índice del pedido actual mostrado
  int _unreadNotifications = 0;
  final MapController _mapController = MapController();

  // Estado de disponibilidad del repartidor
  bool? _repartidorDisponible;
  bool _cargandoDisponibilidad = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadNotifications();
    _initSocketNotifications();
    _startPeriodicRefresh();

    // Verificar disponibilidad si es repartidor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarDisponibilidadRepartidor();
    });
  }

  /// Verifica si el repartidor está disponible al abrir la app
  Future<void> _verificarDisponibilidadRepartidor() async {
    final authProvider = context.read<AuthProvider>();
    final tipoUsuario = authProvider.usuario?['tipoUsuario'] ?? 'cliente';

    if (tipoUsuario != 'repartidor') return;

    setState(() => _cargandoDisponibilidad = true);

    try {
      final perfil = await RepartidorService.obtenerPerfilRepartidor();

      final disponible = perfil['disponible'] ?? false;

      if (mounted) {
        setState(() {
          _repartidorDisponible = disponible;
          _cargandoDisponibilidad = false;
        });

        // Si no está disponible, mostrar diálogo para activar
        if (!disponible) {
          _mostrarDialogoActivarDisponibilidad();
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error verificando disponibilidad: $e');
      if (mounted) {
        setState(() => _cargandoDisponibilidad = false);
      }
    }
  }

  /// Muestra diálogo para activar disponibilidad
  void _mostrarDialogoActivarDisponibilidad() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFDB827)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Activa tu disponibilidad',
                style: TextStyle(
                  color: AppTheme.textPrimaryColor,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Tu disponibilidad está desactivada. Actívala para recibir notificaciones de nuevos pedidos disponibles.',
          style: TextStyle(color: AppTheme.textSecondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Más tarde',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _activarDisponibilidad();
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('Activar ahora'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Activa la disponibilidad del repartidor
  Future<void> _activarDisponibilidad() async {
    setState(() => _cargandoDisponibilidad = true);

    try {
      await RepartidorService.cambiarDisponibilidad(true);

      if (mounted) {
        setState(() => _repartidorDisponible = true);

        // Reconectar socket para recibir notificaciones
        final token = context.read<AuthProvider>().token;
        if (token != null) {
          _homeSocket.connect(baseUrl: AppConstants.socketUrl, token: token);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Disponibilidad activada. Ahora recibirás notificaciones de pedidos.',
            ),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al activar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargandoDisponibilidad = false);
      }
    }
  }

  /// Inicia refresh periódico para actualizar lista de pedidos activos
  void _startPeriodicRefresh() {
    // OPTIMIZACIÓN: Reducido de 10s a 30s para disminuir carga en servidor
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _refreshActivePedidos();
      }
    });
  }

  /// Refresca la lista de pedidos activos desde el backend
  Future<void> _refreshActivePedidos() async {
    try {
      final lista = await PedidoService.misPedidos();
      List<Map<String, dynamic>> encontrados = [];
      for (final p in lista) {
        final estado = (p['estado'] ?? '').toString();
        if (estado == 'en_camino' || estado == 'recogido') {
          encontrados.add(Map<String, dynamic>.from(p));
        }
      }

      if (!mounted) return;

      if (encontrados.isEmpty) {
        // No hay pedidos activos, limpiar todo
        setState(() {
          _pedidosActivosList = [];
          _activePedidoCache = null;
          _currentPedidoIndex = 0;
          _driverLatLngHome = null;
          _joinedPedidoId = null;
        });
      } else {
        // Hay pedidos activos, actualizar lista
        setState(() {
          _pedidosActivosList = encontrados;

          // Si el pedido actual ya no está en la lista, resetear al primero
          final currentId = _activePedidoCache?['id'];
          final stillExists = encontrados.any((p) => p['id'] == currentId);

          if (!stillExists) {
            _currentPedidoIndex = 0;
            _activePedidoCache = encontrados.first;
            _joinedPedidoId = null;
            _driverLatLngHome = null;
          } else {
            // Actualizar el cache con datos frescos del pedido actual
            _activePedidoCache = encontrados[_currentPedidoIndex];
          }
        });
      }
    } catch (_) {
      // Silenciar errores de refresh periódico
    }
  }

  /// Inicializa el socket para recibir notificaciones en tiempo real
  void _initSocketNotifications() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    // Conectar socket
    _homeSocket.connect(baseUrl: AppConstants.socketUrl, token: token);

    // Escuchar notificaciones
    _notificationSub?.cancel();
    _notificationSub = _homeSocket.notificationStream.listen((data) {
      if (!mounted) return;

      final title = data['title']?.toString() ?? 'Nueva notificación';
      final body = data['body']?.toString() ?? '';

      // Mostrar SnackBar con la notificación
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications, color: Color(0xFFFDB827)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F3A4A),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'VER',
            textColor: const Color(0xFFFDB827),
            onPressed: () {
              // Navegar a pantalla de notificaciones
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ),
      );

      // Actualizar contador de notificaciones no leídas
      _loadUnreadNotifications();

      // Si la notificación indica que un pedido fue entregado, limpiar el tracking
      if (title.toLowerCase().contains('entregado') ||
          body.toLowerCase().contains('entregado') ||
          title.toLowerCase().contains('completado') ||
          body.toLowerCase().contains('completado')) {
        if (mounted) {
          setState(() {
            _pedidosActivosList = [];
            _activePedidoCache = null;
            _currentPedidoIndex = 0;
            _driverLatLngHome = null;
            _joinedPedidoId = null;
          });
          // Forzar desconexión del socket de tracking
          _homeSocket.disconnect();
          // Limpiar provider inmediatamente y recargar
          if (mounted) {
            context.read<PedidosProvider>().clear();
            context.read<PedidosProvider>().cargarMisPedidos();
          }
        }
      }
    });
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final notificaciones = await PedidoService.obtenerNotificaciones();
      final unreadCount = notificaciones
          .where((n) => !(n['leida'] ?? false))
          .length;
      if (mounted) {
        setState(() {
          _unreadNotifications = unreadCount;
        });
      }
    } catch (e) {
      // Silenciar error
    }
  }

  @override
  void dispose() {
    _homeSub?.cancel();
    _notificationSub?.cancel();
    _homeSocket.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // Colores por rol para el home
  Color _getRoleColor(String tipoUsuario) {
    switch (tipoUsuario) {
      case 'vendedor':
        return AppTheme.vendedorColor;
      case 'repartidor':
        return AppTheme.repartidorColor;
      case 'cliente':
      default:
        return AppTheme.clienteColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final tipoUsuario = authProvider.usuario?['tipoUsuario'] ?? 'cliente';
        final roleColor = _getRoleColor(tipoUsuario);

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: _buildAppBar(context, roleColor),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildHomeContent(context, authProvider, tipoUsuario),
          ),
        );
      },
    );
  }

  Widget _buildHomeContent(
    BuildContext context,
    AuthProvider authProvider,
    String tipoUsuario,
  ) {
    // Mostrar contenido según el rol
    switch (tipoUsuario) {
      case 'vendedor':
        return _buildVendedorHome(context, authProvider);
      case 'repartidor':
        return _buildRepartidorHome(context, authProvider);
      case 'cliente':
      default:
        return _buildClienteHome(context, authProvider);
    }
  }

  // ===== HOME PARA CLIENTE =====
  Widget _buildClienteHome(BuildContext context, AuthProvider authProvider) {
    final nombre = authProvider.usuario?['nombre'] ?? 'Usuario';
    final pedidosProvider = context.watch<PedidosProvider>();

    // Cargar pedidos una sola vez al entrar (cuando aún no ha cargado nada)
    if (!pedidosProvider.loading && pedidosProvider.pedidos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // doble-check por seguridad
        if (!pedidosProvider.loading && pedidosProvider.pedidos.isEmpty) {
          pedidosProvider.cargarMisPedidos();
        }
      });
    }

    // Si aún no hay pedido activo, forzar un refresh controlado para reflejar
    // cambios que pudieron ocurrir en otra app (repartidor).
    if (pedidosProvider.pedidoActivo == null) {
      final now = DateTime.now();
      final shouldRefresh =
          _lastPedidosFetch == null ||
          now.difference(_lastPedidosFetch!).inSeconds >= 5;
      if (shouldRefresh) {
        _lastPedidosFetch = now;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          pedidosProvider.cargarMisPedidos();
        });
      }
    }

    // Fallback: si el Provider aún no trae activo, intenta obtenerlo directo del backend
    if (pedidosProvider.pedidoActivo == null && _activePedidoCache == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final lista = await PedidoService.misPedidos();
          List<Map<String, dynamic>> encontrados = [];
          for (final p in lista) {
            final estado = (p['estado'] ?? '').toString();
            if (estado == 'en_camino' || estado == 'recogido') {
              encontrados.add(Map<String, dynamic>.from(p));
            }
          }

          if (!mounted) return;
          if (encontrados.isNotEmpty) {
            setState(() {
              _pedidosActivosList = encontrados;
              _activePedidoCache = encontrados.first;
              _currentPedidoIndex = 0;
            });
          } else {
            // Asegurarse de limpiar cualquier rastro de pedidos previos
            setState(() {
              _pedidosActivosList = [];
              _activePedidoCache = null;
              _currentPedidoIndex = 0;
              _driverLatLngHome = null;
              _joinedPedidoId = null;
            });
          }
        } catch (_) {
          // ignorar
        }
      });
    }
    // Si el Provider no tiene activo pero nosotros sí tenemos cache,
    // validar contra backend y actualizar lista de pedidos activos
    else if (pedidosProvider.pedidoActivo == null &&
        _activePedidoCache != null) {
      final now = DateTime.now();
      final shouldRefresh =
          _lastPedidosFetch == null ||
          now.difference(_lastPedidosFetch!).inSeconds >= 5;
      if (shouldRefresh) {
        _lastPedidosFetch = now;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final lista = await PedidoService.misPedidos();
            List<Map<String, dynamic>> encontrados = [];
            for (final p in lista) {
              final estado = (p['estado'] ?? '').toString();
              if (estado == 'en_camino' || estado == 'recogido') {
                encontrados.add(Map<String, dynamic>.from(p));
              }
            }

            if (!mounted) return;
            if (encontrados.isEmpty) {
              // No hay pedidos activos, limpiar todo
              setState(() {
                _pedidosActivosList = [];
                _activePedidoCache = null;
                _currentPedidoIndex = 0;
                _driverLatLngHome = null;
                _joinedPedidoId = null;
              });
            } else {
              // Hay pedidos activos, actualizar lista y mantener índice si es posible
              setState(() {
                _pedidosActivosList = encontrados;
                // Si el pedido actual ya no está en la lista, ir al primero
                final currentId = _activePedidoCache?['id'];
                final stillExists = encontrados.any(
                  (p) => p['id'] == currentId,
                );
                if (!stillExists) {
                  _currentPedidoIndex = 0;
                  _activePedidoCache = encontrados.first;
                  _joinedPedidoId = null; // Forzar reconexión al nuevo pedido
                }
              });
            }
          } catch (_) {
            // ignorar
          }
        });
      }
    }

    // Iniciar tracking live en Home si hay pedido activo
    final token = context.read<AuthProvider>().token;
    final ap = (pedidosProvider.pedidoActivo ?? _activePedidoCache);
    final String? apId = ap != null ? (ap['id'] as String?) : null;
    final String? apNumero = ap != null
        ? (ap['numeroPedido'] as String?)
        : null;
    if (apId != null && token != null && _joinedPedidoId != apId) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Primero intentar obtener ubicación inicial del repartidor desde API
        final repartidorId = ap?['repartidorId'] as String?;
        if (repartidorId != null) {
          try {
            final ubicacion =
                await RepartidorService.obtenerUbicacionRepartidor(
                  repartidorId,
                );
            if (ubicacion != null) {
              final lat = (ubicacion['lat'] as num?)?.toDouble();
              final lng = (ubicacion['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final initialLocation = LatLng(lat, lng);
                setState(() {
                  _driverLatLngHome = initialLocation;
                });
                // Centrar mapa en la ubicación inicial
                _mapController.move(initialLocation, 15);
              }
            }
          } catch (e) {
            // Silenciar error de ubicación inicial
          }
        }

        // Conectar socket para actualizaciones en tiempo real
        if (!_homeSocket.isConnected) {
          _homeSocket.connect(baseUrl: AppConstants.socketUrl, token: token);
          await Future.delayed(const Duration(milliseconds: 600));
        }
        await _homeSocket.joinPedido(apId);

        _homeSub?.cancel();
        _homeSub = _homeSocket.locationStream.listen((data) {
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) return;
          final newLocation = LatLng(lat, lng);
          setState(() {
            _driverLatLngHome = newLocation;
          });
          // Centrar mapa automáticamente en la nueva ubicación del repartidor
          _mapController.move(newLocation, 15);
        });

        setState(() {
          _joinedPedidoId = apId;
        });
      });
    }

    Future<void> abrirRastreo() async {
      // 1) Usar el activo del Provider si existe
      var activo = pedidosProvider.pedidoActivo;

      // 2) Si no hay, forzar fetch inmediato para capturar cambios hechos desde la app del repartidor
      if (activo == null) {
        try {
          final lista = await PedidoService.misPedidos();
          List<Map<String, dynamic>> encontrados = [];
          for (final p in lista) {
            final estado = (p['estado'] ?? '').toString();
            if (estado == 'en_camino' || estado == 'recogido') {
              encontrados.add(Map<String, dynamic>.from(p));
            }
          }

          if (encontrados.isNotEmpty) {
            setState(() {
              _pedidosActivosList = encontrados;
              _activePedidoCache = encontrados.first;
              _currentPedidoIndex = 0;
            });
            activo = encontrados.first;
          }
        } catch (_) {
          // Ignorar, mostraremos el SnackBar abajo
        }
      }

      if (activo == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No tienes un pedido en camino para rastrear.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      final ap2 = activo;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RastrearPedidoScreen(pedidoId: ap2['id']),
        ),
      );
    }

    // Cambiar al siguiente pedido en la lista
    void siguientePedido() {
      if (_pedidosActivosList.length <= 1) return;
      setState(() {
        _currentPedidoIndex =
            (_currentPedidoIndex + 1) % _pedidosActivosList.length;
        _activePedidoCache = _pedidosActivosList[_currentPedidoIndex];
        _joinedPedidoId = null; // Forzar reconexión al nuevo pedido
        _driverLatLngHome = null; // Limpiar ubicación anterior
      });
    }

    // Asegurar que el índice esté dentro de los límites
    if (_pedidosActivosList.isNotEmpty &&
        _currentPedidoIndex >= _pedidosActivosList.length) {
      _currentPedidoIndex = 0;
    }

    // Preview rastreo (solo si hay pedido en_camino o recogido)
    // Usar el pedido actual de la lista para mostrar el correcto
    final pedidoParaMostrar = _pedidosActivosList.isNotEmpty
        ? _pedidosActivosList[_currentPedidoIndex]
        : (pedidosProvider.pedidoActivo ?? _activePedidoCache);

    final estadoPedido = (pedidoParaMostrar?['estado'] ?? '').toString();
    // Mostrar mapa durante en_camino y recogido, ocultar cuando ya está entregado
    final mostrarMapa =
        pedidoParaMostrar != null &&
        (estadoPedido == 'en_camino' || estadoPedido == 'recogido');

    // Obtener número del pedido actual para mostrar en el header

    final String? apNumeroActual = pedidoParaMostrar != null
        ? (pedidoParaMostrar['numeroPedido'] as String?)
        : null;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bienvenida
            _buildWelcomeCard(context, nombre, '👤 Cliente'),
            const SizedBox(height: 16),

            // Preview rastreo (solo si hay pedido en_camino)
            if (mostrarMapa) ...[
              // Header con info del pedido y navegación si hay múltiples
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu repartidor está en camino 🚴',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppTheme.textPrimaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (apNumeroActual != null &&
                            apNumeroActual.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '#$apNumeroActual',
                            style: const TextStyle(
                              color: AppTheme.textSecondaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Indicador de múltiples pedidos
                  if (_pedidosActivosList.length > 1) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.repartidorColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.repartidorColor.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_currentPedidoIndex + 1}/${_pedidosActivosList.length}',
                            style: TextStyle(
                              color: AppTheme.repartidorColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: siguientePedido,
                            child: Icon(
                              Icons.swap_horiz,
                              color: AppTheme.repartidorColor,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Mini mapa de seguimiento en tiempo real
              _buildMapaSeguimiento(),

              const SizedBox(height: 8),
              Text(
                _homeSocket.isConnected
                    ? (_driverLatLngHome != null
                          ? '🟢 Conectado. Recibiendo ubicación del repartidor.'
                          : '🟢 Conectado. Esperando la primera ubicación…')
                    : '🔴 Desconectado. Toca recargar o verifica tu conexión.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
            ] else ...[
              const SizedBox(height: 8),
            ],

            // Acciones rápidas
            Text(
              'Mis Pedidos',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildActionCard(
                  context,
                  icon: Icons.add_shopping_cart,
                  title: 'Nuevo Pedido',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClienteProductosScreen(),
                      ),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  icon: Icons.list,
                  title: 'Mis Pedidos',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClienteMisPedidosScreen(),
                      ),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  icon: Icons.location_on,
                  title: 'Rastrear',
                  onTap: () {
                    // Abre lista de pedidos en camino (soporta múltiples pedidos)
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RastrearPedidoScreen(),
                      ),
                    );
                  },
                ),

                _buildActionCard(
                  context,
                  icon: Icons.star,
                  title: 'Calificaciones',
                  onTap: () {},
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Estadísticas cliente
            Text(
              'Mis Estadísticas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),

            _buildStatsCard(
              children: [
                _buildStatItem('Pedidos Completados', '0', Icons.check_circle),
                const SizedBox(height: 16),
                _buildStatItem('Pedidos Pendientes', '0', Icons.schedule),
                const SizedBox(height: 16),
                _buildStatItem('Gasto Total', '\$0.00', Icons.payment),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== HOME PARA VENDEDOR =====
  Widget _buildVendedorHome(BuildContext context, AuthProvider authProvider) {
    final nombre = authProvider.usuario?['nombre'] ?? 'Usuario';

    return SingleChildScrollView(
      key: const ValueKey('vendedor_home'),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bienvenida con indicador online
            _buildWelcomeCardWithStatus(
              context,
              nombre,
              '🏪 Vendedor',
              AppTheme.vendedorColor,
              true, // online
            ),

            const SizedBox(height: 24),

            // Acciones rápidas
            Text(
              'Mi Negocio',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildActionCard(
                  context,
                  icon: Icons.add_box,
                  title: 'Agregar Producto',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AgregarProductoScreen(),
                      ),
                    );
                  },
                ),

                _buildActionCard(
                  context,
                  icon: Icons.inventory,
                  title: 'Mis Productos',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MisProductosScreen(),
                      ),
                    );
                  },
                ),

                _buildActionCard(
                  context,
                  icon: Icons.shopping_bag,
                  title: 'Mis Pedidos',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VendedorMisPedidosScreen(),
                      ),
                    );
                  },
                ),
                _buildActionCard(
                  context,
                  icon: Icons.trending_up,
                  title: 'Ventas',
                  onTap: () {},
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Estadísticas vendedor
            Text(
              'Mis Ventas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),

            _buildStatsCard(
              children: [
                _buildStatItem('Productos', '0', Icons.inventory_2),
                const SizedBox(height: 16),
                _buildStatItem('Ventas Hoy', '0', Icons.today),
                const SizedBox(height: 16),
                _buildStatItem('Ingresos Totales', '\$0.00', Icons.money),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== HOME PARA REPARTIDOR =====
  Widget _buildRepartidorHome(BuildContext context, AuthProvider authProvider) {
    final nombre = authProvider.usuario?['nombre'] ?? 'Usuario';

    return SingleChildScrollView(
      key: const ValueKey('repartidor_home'),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bienvenida con indicador online
            _buildWelcomeCardWithStatus(
              context,
              nombre,
              '🚚 Repartidor',
              AppTheme.repartidorColor,
              true, // online
            ),

            const SizedBox(height: 24),

            // Acciones rápidas
            Text(
              'Mis Entregas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildActionCard(
                  context,
                  icon: Icons.local_shipping,
                  title: 'Nuevas Entregas',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RepartidorPedidosScreen(),
                      ),
                    );
                  },
                ),

                _buildActionCard(
                  context,
                  icon: Icons.map,
                  title: 'Rutas',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RepartidorRutasScreen(),
                      ),
                    );
                  },
                ),

                _buildActionCard(
                  context,
                  icon: Icons.done_all,
                  title: 'Completadas',
                  onTap: () {},
                ),
                _buildActionCard(
                  context,
                  icon: Icons.payment,
                  title: 'Ganancias',
                  onTap: () {},
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Estadísticas repartidor
            Text(
              'Mis Entregas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 16),

            _buildStatsCard(
              children: [
                _buildStatItem('Entregas Hoy', '0', Icons.today),
                const SizedBox(height: 16),
                _buildStatItem('Completadas', '0', Icons.check_circle),
                const SizedBox(height: 16),
                _buildStatItem('Ganancias Hoy', '\$0.00', Icons.attach_money),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== WIDGETS COMPARTIDOS =====

  PreferredSizeWidget _buildAppBar(BuildContext context, Color roleColor) {
    return AppBar(
      backgroundColor: AppTheme.cardColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: true,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: roleColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/logo.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(width: 8),
          Text(
            'ValleXpress',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.textPrimaryColor,
            ),
          ),
        ],
      ),

      actions: [
        // Icono de notificaciones
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: AppTheme.primaryColor,
                size: 28,
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
                // Recargar contador al volver
                _loadUnreadNotifications();
              },
            ),
            // Badge de notificaciones no leídas (solo si hay)
            if (_unreadNotifications > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),

        PopupMenuButton<String>(
          color: AppTheme.cardColor,
          icon: const Icon(Icons.menu, color: AppTheme.primaryColor, size: 28),

          onSelected: (value) {
            final tipoUsuario =
                context.read<AuthProvider>().usuario?['tipoUsuario'] ??
                'cliente';
            switch (value) {
              case 'perfil':
                Widget profileScreen;
                if (tipoUsuario == 'vendedor') {
                  profileScreen = const VendedorProfileScreen();
                } else if (tipoUsuario == 'repartidor') {
                  profileScreen = RepartidorProfileScreen();
                } else {
                  profileScreen = const ClienteProfileScreen();
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => profileScreen),
                );
                break;
              case 'configuracion':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
                break;
              case 'logout':
                _showLogoutDialog(context);
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<String>(
              value: 'perfil',
              child: Row(
                children: const [
                  Icon(Icons.person, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Mi Perfil',
                    style: TextStyle(color: AppTheme.textPrimaryColor),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'configuracion',
              child: Row(
                children: const [
                  Icon(Icons.settings, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Configuración',
                    style: TextStyle(color: AppTheme.textPrimaryColor),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: const [
                  Icon(Icons.logout, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeCard(BuildContext context, String nombre, String rol) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.cardColor, AppTheme.cardColorLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.waving_hand,
                  color: AppTheme.backgroundColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¡Hola, $nombre!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.textPrimaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
            ),
            child: Text(
              'Bienvenido a ValleXpress $rol',
              style: TextStyle(
                color: AppTheme.accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCardWithStatus(
    BuildContext context,
    String nombre,
    String rol,
    Color roleColor,
    bool isOnline,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.cardColor, AppTheme.cardColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: roleColor.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: roleColor.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [roleColor, roleColor.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: roleColor.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  rol.contains('Vendedor')
                      ? Icons.store
                      : Icons.delivery_dining,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¡Hola, $nombre!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.textPrimaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Indicador online con glow
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: isOnline ? AppTheme.successColor : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: (isOnline ? AppTheme.successColor : Colors.grey)
                          .withOpacity(0.6),
                      blurRadius: 10,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      roleColor.withOpacity(0.3),
                      roleColor.withOpacity(0.1),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: roleColor.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  rol,
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppTheme.successColor.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isOnline ? '● En línea' : '● Desconectado',
                  style: TextStyle(
                    color: isOnline ? AppTheme.successColor : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    final color = accentColor ?? AppTheme.primaryColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.cardColor,
                AppTheme.cardColorLight.withOpacity(0.5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimaryColor,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.cardColor, AppTheme.cardColorLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentColor.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimaryColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text(
          'Cerrar sesión',
          style: TextStyle(color: AppTheme.textPrimaryColor),
        ),
        content: const Text(
          '¿Estás seguro de que deseas cerrar sesión?',
          style: TextStyle(color: AppTheme.textSecondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pop(context);
              Navigator.of(
                context,
              ).pushReplacementNamed(AppConstants.loginRoute);
            },
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Mapa de seguimiento con FlutterMap directo + botones
  Widget _buildMapaSeguimiento() {
    final displayLocation =
        _driverLatLngHome ??
        LatLng(AppConstants.vendorLat, AppConstants.vendorLng);

    // Centrar mapa inmediatamente si tenemos ubicación del repartidor
    if (_driverLatLngHome != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_driverLatLngHome!, 15);
      });
    }

    return SizedBox(
      height: 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: displayLocation,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                // Fondo de respaldo mientras cargan los tiles
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE0E0E0), Color(0xFFBDBDBD)],
                    ),
                  ),
                ),
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.vallexpress.app',
                  maxZoom: 19,
                ),

                // Marcador del repartidor
                if (_driverLatLngHome != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _driverLatLngHome!,
                        width: 46,
                        height: 46,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 2),
                            ),
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                // Marcador de destino (tienda/vendedor)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        AppConstants.vendorLat,
                        AppConstants.vendorLng,
                      ),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 2),
                          ),
                        ),
                        child: const Icon(
                          Icons.store,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Botones de zoom y recargar
            Positioned(
              right: 8,
              bottom: 8,
              child: Column(
                children: [
                  // Botón recargar - reconecta socket y centra mapa en repartidor
                  _buildMapButton(Icons.refresh, () async {
                    // Forzar refresh de pedidos para actualizar estados primero
                    await _refreshActivePedidos();
                    // Reconectar socket si es necesario
                    if (_joinedPedidoId != null) {
                      await _homeSocket.ensureConnected();
                      await _homeSocket.joinPedido(_joinedPedidoId!);
                    }
                    // Centrar mapa en la ubicación del repartidor si está disponible
                    if (_driverLatLngHome != null) {
                      _mapController.move(_driverLatLngHome!, 15);
                    }
                  }),

                  const SizedBox(height: 8),
                  // Zoom in
                  _buildMapButton(Icons.add, () {
                    final z = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, z + 1);
                  }),
                  const SizedBox(height: 8),
                  // Zoom out
                  _buildMapButton(Icons.remove, () {
                    final z = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, z - 1);
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}
