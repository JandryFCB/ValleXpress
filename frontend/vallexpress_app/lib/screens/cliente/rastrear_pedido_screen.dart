import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/pedido_service.dart';
import '../../services/socket_tracking_service.dart';

/// Pantalla de rastreo de pedido - Soporta múltiples pedidos en camino
class RastrearPedidoScreen extends StatefulWidget {
  final String?
  pedidoId; // Opcional: si null, muestra lista de pedidos en camino

  const RastrearPedidoScreen({super.key, this.pedidoId});

  @override
  State<RastrearPedidoScreen> createState() => _RastrearPedidoScreenState();
}

class _RastrearPedidoScreenState extends State<RastrearPedidoScreen> {
  // Datos del pedido
  late Future<dynamic> _pedidoFuture;
  Map<String, dynamic>?
  _currentPedido; // Estado actual del pedido para UI reactiva

  // Lista de pedidos en camino (cuando no se especifica pedidoId)
  List<Map<String, dynamic>> _pedidosEnCamino = [];
  bool _cargandoLista = false;

  // Socket y tracking - MISMO patrón que HomeScreen
  final TrackingSocketService _socketService = TrackingSocketService();
  StreamSubscription<Map<String, dynamic>>? _locationSub;
  LatLng? _driverLocation;
  bool _isConnected = false;
  final MapController _mapController = MapController();

  // Timer para verificar estado del pedido periódicamente
  Timer? _estadoCheckTimer;

  // Estado actual del pedido para controlar visibilidad del mapa
  String? _currentEstado;

  @override
  void initState() {
    super.initState();
    if (widget.pedidoId != null) {
      // Modo tracking directo: cargar pedido específico
      _pedidoFuture = _cargarPedido(widget.pedidoId!);
    } else {
      // Modo lista: cargar todos los pedidos en camino
      _pedidoFuture = _cargarPedidosEnCamino();
    }
  }

  /// Carga TODOS los pedidos en camino del cliente
  Future<List<Map<String, dynamic>>> _cargarPedidosEnCamino() async {
    setState(() => _cargandoLista = true);
    try {
      final lista = await PedidoService.misPedidos();
      final enCamino = lista
          .where((p) {
            final estado = (p['estado'] ?? '').toString();
            return estado == 'en_camino' || estado == 'recogido';
          })
          .cast<Map<String, dynamic>>()
          .toList();

      setState(() {
        _pedidosEnCamino = enCamino;
        _cargandoLista = false;
      });
      return enCamino;
    } catch (e) {
      setState(() => _cargandoLista = false);
      rethrow;
    }
  }

  /// Carga un pedido específico y SI está en camino, inicia tracking
  Future<dynamic> _cargarPedido(String pedidoId) async {
    final pedido = await PedidoService.obtenerPorId(pedidoId);

    // Actualizar estado actual
    final estado = (pedido?['estado'] ?? '').toString();
    if (mounted) {
      setState(() {
        _currentEstado = estado;
      });
    }

    // Si está en camino, iniciar tracking inmediatamente (igual que Home)
    if (estado == 'en_camino' || estado == 'recogido') {
      // Pequeño delay para asegurar que el context esté listo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _iniciarTracking(pedidoId);
      });
    } else {
      // Si NO está en camino, detener tracking y limpiar estado
      _detenerTracking();
    }

    return pedido;
  }

  /// Inicia tracking - Conexión automática robusta
  void _iniciarTracking(String pedidoId) async {
    // Iniciar timer de verificación de estado (solo uno)
    _estadoCheckTimer ??= Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!mounted || widget.pedidoId == null) {
        timer.cancel();
        _estadoCheckTimer = null;
        return;
      }

      try {
        final pedido = await PedidoService.obtenerPorId(widget.pedidoId!);
        final estado = (pedido?['estado'] ?? '').toString();

        // Actualizar estado actual
        if (mounted) {
          setState(() {
            _currentEstado = estado;
          });
        }

        // Si ya no está en camino, detener tracking y refrescar UI
        if (estado != 'en_camino' && estado != 'recogido') {
          if (mounted) {
            _detenerTracking();
            setState(() {
              _pedidoFuture = Future.value(pedido);
            });
          }
          timer.cancel();
        }
      } catch (e) {
        // Silenciar errores de polling
      }
    });

    final token = context.read<AuthProvider>().token;

    if (token == null) return;

    // Mostrar estado de conectando
    if (mounted) {
      setState(() => _isConnected = false);
    }

    // Conectar socket (sin dispose previo que cierra los streams permanentemente)

    _socketService.connect(baseUrl: AppConstants.socketUrl, token: token);

    // Esperar a que el socket esté conectado (máximo 3 segundos)
    var attempts = 0;
    while (!_socketService.isConnected && attempts < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    // Si no se conectó, intentar reconectar
    if (!_socketService.isConnected) {
      await _socketService.ensureConnected();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Unirse al pedido
    if (_socketService.isConnected) {
      await _socketService.joinPedido(pedidoId);
    }

    // Escuchar ubicaciones
    _locationSub?.cancel();
    _locationSub = _socketService.locationStream.listen((data) {
      // Verificar que el pedido sigue en camino antes de actualizar ubicación
      if (_currentEstado != 'en_camino' && _currentEstado != 'recogido') {
        return; // Ignorar actualizaciones si el pedido ya no está en camino
      }

      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      if (mounted) {
        setState(() {
          _driverLocation = LatLng(lat, lng);
        });
        // Auto-centrar mapa en la ubicación del repartidor
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(LatLng(lat, lng), 15);
        });
      }
    });

    if (mounted) {
      setState(() => _isConnected = _socketService.isConnected);
    }
  }

  /// Navega al tracking de un pedido específico
  void _abrirTrackingPedido(String pedidoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RastrearPedidoScreen(pedidoId: pedidoId),
      ),
    );
  }

  /// Detiene tracking y limpia estado
  void _detenerTracking() {
    _estadoCheckTimer?.cancel();
    _estadoCheckTimer = null;
    _locationSub?.cancel();
    _locationSub = null;
    if (mounted) {
      setState(() {
        _driverLocation = null;
        _isConnected = false;
      });
    }
  }

  /// Refrescar - reconecta socket o recarga lista
  Future<void> _refrescar() async {
    setState(() {
      if (widget.pedidoId != null) {
        _pedidoFuture = _cargarPedido(widget.pedidoId!);
      } else {
        _pedidoFuture = _cargarPedidosEnCamino();
      }
    });
  }

  @override
  void dispose() {
    _estadoCheckTimer?.cancel();
    _locationSub?.cancel();
    // No llamar dispose() del socket service aquí - es un singleton compartido
    // Solo cancelamos la suscripción a este screen específico
    _mapController.dispose();
    super.dispose();
  }

  // ========== UI HELPERS ==========

  String _estadoTexto(String estado) {
    const mapa = {
      'pendiente': 'Pendiente',
      'confirmado': 'Confirmado',
      'preparando': 'Preparando',
      'listo': 'Listo',
      'en_camino': 'En camino',
      'entregado': 'Entregado',
      'recibido_cliente': 'Recibido',
      'cancelado': 'Cancelado',
    };
    return mapa[estado] ?? estado.replaceAll('_', ' ');
  }

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'pendiente':
        return const Color(0xFF8E9AAF);
      case 'confirmado':
        return const Color(0xFF2D6A9F);
      case 'preparando':
        return const Color(0xFFB08900);
      case 'listo':
        return const Color(0xFF2E7D32);
      case 'en_camino':
        return const Color(0xFF1565C0);
      case 'entregado':
      case 'recibido_cliente':
        return const Color(0xFF2E7D32);
      case 'cancelado':
        return const Color(0xFFD32F2F);
      default:
        return Colors.grey;
    }
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F3A4A),
        elevation: 0,
        title: Text(
          widget.pedidoId != null ? 'Rastrear pedido' : 'Tus pedidos en camino',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh, color: Color(0xFFFDB827)),
            onPressed: _refrescar,
          ),
        ],
      ),
      body: FutureBuilder<dynamic>(
        future: _pedidoFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildErrorView('Error: ${snapshot.error}');
          }

          // Modo lista: mostrar pedidos en camino
          if (widget.pedidoId == null) {
            final pedidos = snapshot.data as List<Map<String, dynamic>>?;
            if (pedidos == null || pedidos.isEmpty) {
              return _buildSinPedidosView();
            }
            return _buildListaPedidos(pedidos);
          }

          // Modo tracking: mostrar mapa directamente
          final pedido = _currentPedido ?? snapshot.data;
          if (pedido == null) {
            return _buildErrorView('Pedido no encontrado');
          }

          final estado = (pedido['estado'] ?? '').toString();
          final numeroPedido = (pedido['numeroPedido'] ?? '').toString();
          final vendedor = pedido['vendedor'];
          final tienda = (vendedor?['nombreNegocio'] ?? '').toString();

          // Usar estado actual si está disponible, sino el del pedido cargado
          final effectiveEstado = _currentEstado ?? estado;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPedidoCard(numeroPedido, tienda, estado),
                  const SizedBox(height: 16),
                  // Usar estado actual del pedido para mostrar/ocultar mapa
                  if (effectiveEstado == 'en_camino' ||
                      effectiveEstado == 'recogido') ...[
                    _buildTrackingSection(),
                  ] else ...[
                    _buildEstadoInfo(effectiveEstado),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Vista cuando no hay pedidos en camino
  Widget _buildSinPedidosView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_shipping_outlined,
              color: Colors.grey,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No tienes pedidos en camino',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando hagas un pedido y esté en camino, podrás rastrearlo aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refrescar,
              icon: const Icon(Icons.refresh),
              label: const Text('Recargar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFDB827),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lista de pedidos en camino
  Widget _buildListaPedidos(List<Map<String, dynamic>> pedidos) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pedidos.length,
      itemBuilder: (context, index) {
        final pedido = pedidos[index];
        final numeroPedido = (pedido['numeroPedido'] ?? '').toString();
        final vendedor = pedido['vendedor'];
        final tienda = (vendedor?['nombreNegocio'] ?? 'Tienda').toString();
        final pedidoId = pedido['id'].toString();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: AppTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: AppTheme.borderColor.withOpacity(0.25),
              width: 1.3,
            ),
          ),
          child: InkWell(
            onTap: () => _abrirTrackingPedido(pedidoId),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDB827).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delivery_dining,
                      color: Color(0xFFFDB827),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          numeroPedido.isNotEmpty ? '#$numeroPedido' : 'Pedido',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '🏪 $tienda',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '🚴 En camino',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Card con información del pedido
  Widget _buildPedidoCard(String numeroPedido, String tienda, String estado) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.borderColor.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_shipping, color: Color(0xFFFDB827), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  numeroPedido.isNotEmpty ? '#$numeroPedido' : 'Pedido',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (tienda.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tienda: $tienda',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _estadoColor(estado),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _estadoTexto(estado),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sección de tracking - Usando FlutterMap directo con botones
  Widget _buildTrackingSection() {
    final displayLocation =
        _driverLocation ??
        LatLng(AppConstants.vendorLat, AppConstants.vendorLng);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ubicación del repartidor',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppTheme.textPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Mapa con FlutterMap directo + botones
        SizedBox(
          height: 320,
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
                    if (_driverLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _driverLocation!,
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
                      // Botón recargar - reconecta socket y centra mapa
                      _buildMapButton(Icons.refresh, () async {
                        if (widget.pedidoId == null) return;
                        await _socketService.ensureConnected();
                        await _socketService.joinPedido(widget.pedidoId!);
                        // Centrar mapa en la ubicación del repartidor
                        if (_driverLocation != null) {
                          _mapController.move(_driverLocation!, 15);
                        }
                      }),

                      const SizedBox(height: 8),
                      // Zoom in
                      _buildMapButton(Icons.add, () {
                        final z = _mapController.camera.zoom;
                        _mapController.move(
                          _mapController.camera.center,
                          z + 1,
                        );
                      }),
                      const SizedBox(height: 8),
                      // Zoom out
                      _buildMapButton(Icons.remove, () {
                        final z = _mapController.camera.zoom;
                        _mapController.move(
                          _mapController.camera.center,
                          z - 1,
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Estado de conexión
        Text(
          _socketService.isConnected
              ? (_driverLocation != null
                    ? '🟢 Conectado. Recibiendo ubicación del repartidor.'
                    : '🟢 Conectado. Esperando la primera ubicación…')
              : '🔴 Desconectado. Toca recargar o verifica tu conexión.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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

  /// Info cuando el pedido no está en camino
  Widget _buildEstadoInfo(String estado) {
    // Si está entregado, mostrar botón para marcar como recibido
    if (estado == 'entregado') {
      return _buildEntregadoView();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.borderColor.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFFDB827)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'El pedido está en estado "${_estadoTexto(estado)}". '
              'El tracking solo está disponible cuando está "En camino".',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vista cuando el pedido está entregado - permite marcar como recibido
  Widget _buildEntregadoView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2E7D32).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF2E7D32),
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            '¡Tu pedido ha sido entregado! 🎉',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Por favor confirma que recibiste tu pedido para completar el proceso.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _marcarRecibido,
            icon: const Icon(Icons.thumb_up),
            label: const Text('Confirmar recepción'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Marcar pedido como recibido
  Future<void> _marcarRecibido() async {
    if (widget.pedidoId == null) return;

    try {
      setState(() {
        _pedidoFuture = _cargarPedido(widget.pedidoId!);
      });

      await PedidoService.marcarRecibidoCliente(widget.pedidoId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido marcado como recibido. ¡Gracias!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }

      // Recargar para mostrar nuevo estado
      await _refrescar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al confirmar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Vista de error
  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refrescar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFDB827),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
