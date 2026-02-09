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
    setState(() {
      _pedidoSeleccionado = pedido;

      // Obtener ubicación del vendedor (origen)
      final vendedor = pedido['vendedor'];
      if (vendedor != null) {
        final lat =
            vendedor['latitud'] ??
            vendedor['ubicacionLatitud'] ??
            vendedor['lat'];
        final lng =
            vendedor['longitud'] ??
            vendedor['ubicacionLongitud'] ??
            vendedor['lng'];
        if (lat != null && lng != null) {
          _ubicacionVendedor = LatLng(
            double.tryParse(lat.toString()) ?? AppConstants.vendorLat,
            double.tryParse(lng.toString()) ?? AppConstants.vendorLng,
          );
          if (kDebugMode) {
            print(
              '📍 Vendedor ubicación: ${_ubicacionVendedor!.latitude}, ${_ubicacionVendedor!.longitude}',
            );
          }
        }
      }

      // Obtener ubicación del cliente (destino) desde direccionEntrega
      final direccionEntrega =
          pedido['direccionEntrega'] ?? pedido['direccion'];
      if (direccionEntrega != null) {
        final lat = direccionEntrega['latitud'] ?? direccionEntrega['lat'];
        final lng = direccionEntrega['longitud'] ?? direccionEntrega['lng'];
        if (lat != null && lng != null) {
          _ubicacionCliente = LatLng(
            double.tryParse(lat.toString()) ?? AppConstants.clientLat,
            double.tryParse(lng.toString()) ?? AppConstants.clientLng,
          );
          if (kDebugMode) {
            print(
              '📍 Cliente ubicación: ${_ubicacionCliente!.latitude}, ${_ubicacionCliente!.longitude}',
            );
          }
        }
      }
    });

    // Centrar mapa en la ruta si tenemos ambas ubicaciones
    if (_ubicacionVendedor != null && _ubicacionCliente != null) {
      _centrarMapaEnRuta();
    }
  }

  void _centrarMapaEnRuta() {
    // Calcular centro incluyendo las 3 ubicaciones si están disponibles
    final puntos = <LatLng>[];
    if (_ubicacionRepartidor != null) puntos.add(_ubicacionRepartidor!);
    if (_ubicacionVendedor != null) puntos.add(_ubicacionVendedor!);
    if (_ubicacionCliente != null) puntos.add(_ubicacionCliente!);

    if (puntos.isEmpty) return;
    if (puntos.length == 1) {
      _mapController.move(puntos.first, 15);
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

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  Future<void> _abrirEnGoogleMaps() async {
    if (_ubicacionVendedor == null || _ubicacionCliente == null) {
      _mostrarError('No hay coordenadas disponibles');
      return;
    }
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=${_ubicacionVendedor!.latitude},${_ubicacionVendedor!.longitude}&destination=${_ubicacionCliente!.latitude},${_ubicacionCliente!.longitude}&travelmode=driving';
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

  String _obtenerDireccionTexto(Map<String, dynamic>? direccion) {
    if (direccion == null) return 'Dirección no disponible';
    final calle = direccion['calle'] ?? direccion['direccion'] ?? '';
    final ciudad = direccion['ciudad'] ?? '';
    final referencia = direccion['referencia'] ?? '';
    final partes = [
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

        if (_ubicacionVendedor != null && _ubicacionCliente != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_ubicacionVendedor!, _ubicacionCliente!],
                color: AppTheme.primaryColor,
                strokeWidth: 4,
              ),
            ],
          ),
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
    final direccion = pedido['direccion'] ?? pedido['direccionEntrega'];
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
              titulo: 'Recoger en',
              direccion: _ubicacionVendedor != null
                  ? '${_obtenerDireccionTexto(vendedor)}\n(Lat: ${_ubicacionVendedor!.latitude.toStringAsFixed(4)}, Lng: ${_ubicacionVendedor!.longitude.toStringAsFixed(4)})'
                  : _obtenerDireccionTexto(vendedor),
            ),

            const SizedBox(height: 12),
            _buildDireccionRow(
              icon: Icons.person_pin,
              color: AppTheme.clienteColor,
              titulo: 'Entregar en',
              direccion: _ubicacionCliente != null
                  ? '${_obtenerDireccionTexto(direccion)}\n(Lat: ${_ubicacionCliente!.latitude.toStringAsFixed(4)}, Lng: ${_ubicacionCliente!.longitude.toStringAsFixed(4)})'
                  : _obtenerDireccionTexto(direccion),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _marcarRecogido(pedido['id'].toString()),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Recogido'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.repartidorColor,
                      side: BorderSide(color: AppTheme.repartidorColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
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
}
