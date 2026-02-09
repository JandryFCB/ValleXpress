import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/repartidor_pedidos_service.dart';
import '../../services/pedido_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class RepartidorRutasScreen extends StatefulWidget {
  const RepartidorRutasScreen({super.key});

  @override
  State<RepartidorRutasScreen> createState() => _RepartidorRutasScreenState();
}

class _RepartidorRutasScreenState extends State<RepartidorRutasScreen> {
  List<Map<String, dynamic>> _pedidosAsignados = [];
  bool _isLoading = true;
  Map<String, dynamic>? _pedidoSeleccionado;
  final MapController _mapController = MapController();
  bool _mapaListo = false;

  LatLng? _ubicacionVendedor;
  LatLng? _ubicacionCliente;
  LatLng? _ubicacionRepartidor;
  StreamSubscription<Position>? _gpsSubscription;

  @override
  void initState() {
    super.initState();
    _iniciarGPS();
    _cargarPedidosAsignados();
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ===== GPS DEL REPARTIDOR =====
  Future<void> _iniciarGPS() async {
    // Verificar permisos
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // Obtener posición inicial
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _ubicacionRepartidor = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      // Si falla, usar ubicación por defecto
      setState(() {
        _ubicacionRepartidor = LatLng(
          AppConstants.vendorLat,
          AppConstants.vendorLng,
        );
      });
    }

    // Escuchar cambios de posición
    _gpsSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 10, // Actualizar cada 10 metros
          ),
        ).listen((Position position) {
          if (mounted) {
            setState(() {
              _ubicacionRepartidor = LatLng(
                position.latitude,
                position.longitude,
              );
            });
          }
        });
  }

  Future<void> _cargarPedidosAsignados() async {
    try {
      setState(() => _isLoading = true);
      final pedidos = List<Map<String, dynamic>>.from(
        await RepartidorPedidosService.obtenerPedidos(),
      );

      if (kDebugMode) {
        print('📦 Pedidos cargados: ${pedidos.length}');
        if (pedidos.isNotEmpty) {
          print('📦 Primer pedido: ${pedidos.first}');
        }
      }

      setState(() {
        _pedidosAsignados = pedidos;
        _isLoading = false;
      });
      if (pedidos.isNotEmpty) {
        _seleccionarPedido(pedidos.first);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _mostrarError('Error al cargar pedidos: $e');
    }
  }

  void _seleccionarPedido(Map<String, dynamic> pedido) {
    if (kDebugMode) {
      print('🎯 Seleccionando pedido: ${pedido['id']}');
      print('🎯 Vendedor data: ${pedido['vendedor']}');
      print('🎯 DireccionEntrega data: ${pedido['direccionEntrega']}');
    }

    setState(() {
      _pedidoSeleccionado = pedido;

      // ===== OBTENER UBICACIÓN DEL VENDEDOR =====
      final vendedor = pedido['vendedor'];
      if (vendedor != null) {
        // Intentar obtener latitud de diferentes campos posibles
        final lat =
            vendedor['latitud'] ??
            vendedor['ubicacionLatitud'] ??
            vendedor['lat'] ??
            vendedor['latitude'];

        final lng =
            vendedor['longitud'] ??
            vendedor['ubicacionLongitud'] ??
            vendedor['lng'] ??
            vendedor['longitude'] ??
            vendedor['long'];

        if (kDebugMode) {
          print('🗺️ Vendedor raw lat: $lat, lng: $lng');
        }

        if (lat != null && lng != null) {
          final latDouble = double.tryParse(lat.toString());
          final lngDouble = double.tryParse(lng.toString());

          if (latDouble != null && lngDouble != null) {
            _ubicacionVendedor = LatLng(latDouble, lngDouble);
            if (kDebugMode) {
              print(
                '✅ Vendedor ubicación: ${_ubicacionVendedor!.latitude}, ${_ubicacionVendedor!.longitude}',
              );
            }
          }
        }
      }

      // ===== OBTENER UBICACIÓN DEL CLIENTE =====
      // La dirección de entrega viene en direccionEntrega o direccion
      final direccionEntrega =
          pedido['direccionEntrega'] ?? pedido['direccion'];

      if (direccionEntrega != null) {
        final lat =
            direccionEntrega['latitud'] ??
            direccionEntrega['lat'] ??
            direccionEntrega['latitude'];

        final lng =
            direccionEntrega['longitud'] ??
            direccionEntrega['lng'] ??
            direccionEntrega['longitude'] ??
            direccionEntrega['long'];

        if (kDebugMode) {
          print('🗺️ Cliente raw lat: $lat, lng: $lng');
        }

        if (lat != null && lng != null) {
          final latDouble = double.tryParse(lat.toString());
          final lngDouble = double.tryParse(lng.toString());

          if (latDouble != null && lngDouble != null) {
            _ubicacionCliente = LatLng(latDouble, lngDouble);
            if (kDebugMode) {
              print(
                '✅ Cliente ubicación: ${_ubicacionCliente!.latitude}, ${_ubicacionCliente!.longitude}',
              );
            }
          }
        }
      }
    });

    // No centrar el mapa aquí, esperar a que el widget esté listo
    if (kDebugMode) {
      print(
        '📍 Ubicaciones - Vendedor: $_ubicacionVendedor, Cliente: $_ubicacionCliente, Repartidor: $_ubicacionRepartidor',
      );
    }
  }

  void _centrarMapaEnRuta() {
    // Verificar que el mapa esté listo
    if (!_mapaListo) {
      if (kDebugMode) {
        print('⏳ Mapa no listo aún, esperando...');
      }
      return;
    }

    // Calcular centro incluyendo las 3 ubicaciones si están disponibles
    final puntos = <LatLng>[];
    if (_ubicacionRepartidor != null) puntos.add(_ubicacionRepartidor!);
    if (_ubicacionVendedor != null) puntos.add(_ubicacionVendedor!);
    if (_ubicacionCliente != null) puntos.add(_ubicacionCliente!);

    if (puntos.isEmpty) return;
    if (puntos.length == 1) {
      try {
        _mapController.move(puntos.first, 15);
      } catch (e) {
        if (kDebugMode) print('⚠️ Error moviendo mapa: $e');
      }
      return;
    }

    double minLat = puntos.first.latitude;
    double maxLat = puntos.first.latitude;
    double minLng = puntos.first.longitude;
    double maxLng = puntos.first.longitude;

    for (final punto in puntos) {
      if (punto.latitude < minLat) minLat = punto.latitude;
      if (punto.latitude > maxLat) maxLat = punto.latitude;
      if (punto.longitude < minLng) minLng = punto.longitude;
      if (punto.longitude > maxLng) maxLng = punto.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Calcular zoom basado en la distancia máxima
    final maxDistance = Distance().as(
      LengthUnit.Kilometer,
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    double zoom = 11;
    if (maxDistance < 1) {
      zoom = 15;
    } else if (maxDistance < 3) {
      zoom = 14;
    } else if (maxDistance < 5) {
      zoom = 13;
    } else if (maxDistance < 10) {
      zoom = 12;
    }

    try {
      _mapController.move(LatLng(centerLat, centerLng), zoom);
      if (kDebugMode) {
        print('✅ Mapa centrado en: $centerLat, $centerLng (zoom: $zoom)');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Error al centrar mapa: $e');
    }
  }

  Future<void> _abrirEnGoogleMaps() async {
    // Usar ubicación del repartidor como origen, o del vendedor si no hay repartidor
    final origen = _ubicacionRepartidor ?? _ubicacionVendedor;

    if (origen == null || _ubicacionCliente == null) {
      _mostrarError('No hay coordenadas disponibles para navegar');
      return;
    }

    // Construir URL con waypoints: Repartidor -> Vendedor -> Cliente
    // Si el repartidor ya está cerca del vendedor, solo mostrar ruta al cliente
    String url;
    if (_ubicacionRepartidor != null && _ubicacionVendedor != null) {
      // Ruta completa: Repartidor -> Vendedor -> Cliente
      url =
          'https://www.google.com/maps/dir/?api=1'
          '&origin=${_ubicacionRepartidor!.latitude},${_ubicacionRepartidor!.longitude}'
          '&waypoints=${_ubicacionVendedor!.latitude},${_ubicacionVendedor!.longitude}'
          '&destination=${_ubicacionCliente!.latitude},${_ubicacionCliente!.longitude}'
          '&travelmode=driving';
    } else {
      // Solo origen -> destino
      url =
          'https://www.google.com/maps/dir/?api=1'
          '&origin=${origen.latitude},${origen.longitude}'
          '&destination=${_ubicacionCliente!.latitude},${_ubicacionCliente!.longitude}'
          '&travelmode=driving';
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _mostrarError('No se pudo abrir Google Maps');
    }
  }

  Future<void> _marcarRecogido(String pedidoId) async {
    try {
      setState(() => _isLoading = true);
      await PedidoService.marcarRecogido(pedidoId);
      setState(() => _isLoading = false);
      _mostrarExito(
        'Pedido marcado como recogido. El cliente ha sido notificado.',
      );
      await _cargarPedidosAsignados();
    } catch (e) {
      setState(() => _isLoading = false);
      _mostrarError('Error al marcar recogido: $e');
    }
  }

  Future<void> _marcarEntregado(String pedidoId) async {
    try {
      setState(() => _isLoading = true);
      await PedidoService.marcarEntregado(pedidoId);
      setState(() => _isLoading = false);
      _mostrarExito(
        'Pedido marcado como entregado. Esperando confirmación del cliente.',
      );
      await _cargarPedidosAsignados();
    } catch (e) {
      setState(() => _isLoading = false);
      _mostrarError('Error al marcar entregado: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
    );
  }

  String _obtenerDireccionTexto(
    Map<String, dynamic>? data, {
    bool esVendedor = false,
  }) {
    if (data == null) return 'Dirección no disponible';

    // Si es vendedor, mostrar nombre del negocio
    if (esVendedor) {
      final nombreNegocio =
          data['nombreNegocio'] ?? data['nombre_negocio'] ?? '';
      if (nombreNegocio.isNotEmpty) return nombreNegocio;
    }

    // Para direcciones normales
    final nombre = data['nombre'] ?? '';
    final calle = data['calle'] ?? data['direccion'] ?? '';
    final ciudad = data['ciudad'] ?? '';
    final referencia = data['referencia'] ?? '';
    final partes = [
      nombre,
      calle,
      ciudad,
      referencia,
    ].where((p) => p.isNotEmpty).toList();
    return partes.isEmpty ? 'Dirección no disponible' : partes.join(', ');
  }

  Color _getColorEstado(String? estado) {
    switch (estado) {
      case 'asignado':
        return AppTheme.repartidorColor;
      case 'en_camino':
        return AppTheme.vendedorColor;
      case 'recogido':
        return AppTheme.primaryColor;
      case 'entregado':
        return AppTheme.clienteColor;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        title: const Text('Mis Rutas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarPedidosAsignados,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pedidosAsignados.isEmpty
          ? _buildEmptyState()
          : _buildRutasView(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes pedidos asignados',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los pedidos aparecerán aquí cuando te sean asignados',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _cargarPedidosAsignados,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRutasView() {
    return Column(
      children: [
        Container(
          height: 120,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _pedidosAsignados.length,
            itemBuilder: (context, index) {
              final pedido = _pedidosAsignados[index];
              final isSelected = _pedidoSeleccionado?['id'] == pedido['id'];
              return GestureDetector(
                onTap: () => _seleccionarPedido(pedido),
                child: Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.shopping_bag,
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '#${pedido['numeroPedido'] ?? pedido['id']?.toString().substring(0, 8)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pedido['vendedor']?['nombreNegocio'] ??
                            pedido['vendedor']?['nombre_negocio'] ??
                            'Negocio',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white70
                              : AppTheme.textSecondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.2)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pedido['estado']?.toString().replaceAll('_', ' ') ??
                              'Pendiente',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textPrimaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(child: _buildMapaRuta()),
        if (_pedidoSeleccionado != null) _buildInfoPedido(),
      ],
    );
  }

  Widget _buildMapaRuta() {
    final center =
        _ubicacionVendedor ??
        LatLng(AppConstants.vendorLat, AppConstants.vendorLng);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        onMapReady: () {
          if (kDebugMode) {
            print('✅ Mapa listo!');
          }
          setState(() {
            _mapaListo = true;
          });
          // Ahora sí centrar el mapa
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _centrarMapaEnRuta();
          });
        },
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
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.vallexpress.app',
          tileBuilder: (context, child, tile) {
            return AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 200),
              child: child,
            );
          },
          errorTileCallback: (tile, error, stackTrace) {
            if (kDebugMode) {
              print('❌ Error cargando tile: $error');
            }
          },
        ),

        // Líneas de ruta: Repartidor -> Vendedor -> Cliente
        if (_ubicacionVendedor != null && _ubicacionCliente != null)
          PolylineLayer(
            polylines: [
              // Ruta 1: Repartidor -> Vendedor (línea punteada o diferente color)
              if (_ubicacionRepartidor != null)
                Polyline(
                  points: [_ubicacionRepartidor!, _ubicacionVendedor!],
                  color: AppTheme.repartidorColor,
                  strokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: [10, 10]),
                ),
              // Ruta 2: Vendedor -> Cliente (línea principal)
              Polyline(
                points: [_ubicacionVendedor!, _ubicacionCliente!],
                color: AppTheme.primaryColor,
                strokeWidth: 4,
              ),
            ],
          ),

        // Marcadores
        MarkerLayer(
          markers: [
            // Marcador del repartidor (YO)
            if (_ubicacionRepartidor != null)
              Marker(
                point: _ubicacionRepartidor!,
                width: 56,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.repartidorColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.repartidorColor.withOpacity(0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.delivery_dining,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),

            // Marcador del vendedor (ORIGEN)
            if (_ubicacionVendedor != null)
              Marker(
                point: _ubicacionVendedor!,
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.vendedorColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.store, color: Colors.white, size: 24),
                ),
              ),

            // Marcador del cliente (DESTINO)
            if (_ubicacionCliente != null)
              Marker(
                point: _ubicacionCliente!,
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.clienteColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_pin,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoPedido() {
    final pedido = _pedidoSeleccionado!;
    final vendedor = pedido['vendedor'];
    final direccion = pedido['direccionEntrega'] ?? pedido['direccion'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_bag,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #${pedido['numeroPedido'] ?? pedido['id']?.toString().substring(0, 8)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        vendedor?['nombreNegocio'] ??
                            vendedor?['nombre_negocio'] ??
                            'Negocio',
                        style: TextStyle(
                          color: AppTheme.textSecondaryColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getColorEstado(pedido['estado']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    pedido['estado']?.toString().replaceAll('_', ' ') ??
                        'Pendiente',
                    style: TextStyle(
                      color: _getColorEstado(pedido['estado']),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info de ubicaciones
            _buildDireccionRow(
              icon: Icons.delivery_dining,
              color: AppTheme.repartidorColor,
              titulo: 'Mi ubicación actual',
              direccion: _ubicacionRepartidor != null
                  ? 'Lat: ${_ubicacionRepartidor!.latitude.toStringAsFixed(4)}, Lng: ${_ubicacionRepartidor!.longitude.toStringAsFixed(4)}'
                  : 'Obteniendo ubicación GPS...',
            ),
            const SizedBox(height: 12),

            _buildDireccionRow(
              icon: Icons.store,
              color: AppTheme.vendedorColor,
              titulo: 'Recoger en (Vendedor)',
              direccion: _ubicacionVendedor != null
                  ? '${_obtenerDireccionTexto(vendedor, esVendedor: true)}\n(Lat: ${_ubicacionVendedor!.latitude.toStringAsFixed(4)}, Lng: ${_ubicacionVendedor!.longitude.toStringAsFixed(4)})'
                  : '${_obtenerDireccionTexto(vendedor, esVendedor: true)}\n⚠️ Sin coordenadas',
            ),

            const SizedBox(height: 12),

            _buildDireccionRow(
              icon: Icons.person_pin,
              color: AppTheme.clienteColor,
              titulo: 'Entregar en (Cliente)',
              direccion: _ubicacionCliente != null
                  ? '${_obtenerDireccionTexto(direccion)}\n(Lat: ${_ubicacionCliente!.latitude.toStringAsFixed(4)}, Lng: ${_ubicacionCliente!.longitude.toStringAsFixed(4)})'
                  : '${_obtenerDireccionTexto(direccion)}\n⚠️ Sin coordenadas',
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _abrirEnGoogleMaps,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Navegar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildAccionButton(pedido)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDireccionRow({
    required IconData icon,
    required Color color,
    required String titulo,
    required String direccion,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: AppTheme.textSecondaryColor,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                direccion,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Botón de acción dinámico según el estado del pedido
  Widget _buildAccionButton(Map<String, dynamic> pedido) {
    final estado = pedido['estado']?.toString() ?? '';

    // Si está recogido, mostrar botón "Entregado"
    if (estado == 'recogido') {
      return ElevatedButton.icon(
        onPressed: () => _marcarEntregado(pedido['id'].toString()),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Entregado'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.clienteColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    // Si está en_camino o listo, mostrar botón "Recogido"
    if (estado == 'en_camino' || estado == 'listo') {
      return OutlinedButton.icon(
        onPressed: () => _marcarRecogido(pedido['id'].toString()),
        icon: const Icon(Icons.check_circle),
        label: const Text('Recogido'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.repartidorColor,
          side: BorderSide(color: AppTheme.repartidorColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    // Si está entregado, mostrar botón deshabilitado
    if (estado == 'entregado') {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_empty),
        label: const Text('Esperando cliente'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    // Para otros estados, botón deshabilitado
    return ElevatedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.block),
      label: const Text('No disponible'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
