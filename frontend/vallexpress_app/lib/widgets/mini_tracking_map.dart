import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Fallback colors when map tiles don't load
const Color _kMapFallbackColor = Color(0xFFE0E0E0);
const Color _kMapFallbackColorDark = Color(0xFFBDBDBD);

class MiniTrackingMap extends StatefulWidget {
  final LatLng initialCenter;

  // Ubicaciones
  final LatLng driverLocation;
  final LatLng vendorLocation;
  final LatLng clientLocation;

  // Si true, mueve el marcador del repartidor con animación mock (para demos)
  final bool animateMock;

  // Callback opcional para refrescar (por ejemplo, re-join del socket)
  final VoidCallback? onRefresh;

  const MiniTrackingMap({
    super.key,
    required this.initialCenter,
    required this.driverLocation,
    required this.vendorLocation,
    required this.clientLocation,
    this.animateMock = false,
    this.onRefresh,
  });

  @override
  State<MiniTrackingMap> createState() => _MiniTrackingMapState();
}

class _MiniTrackingMapState extends State<MiniTrackingMap> {
  late final MapController _mapController;
  Timer? _smoothTimer;
  LatLng? _animatedDriver;
  bool _cameraCentered = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _animatedDriver = widget.driverLocation;

    // Animación suave mock (solo si se habilita)
    if (widget.animateMock) {
      _smoothTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        final d = _animatedDriver!;
        final next = LatLng(d.latitude + 0.00005, d.longitude + 0.00005);
        setState(() => _animatedDriver = next);
      });
    }

    // Asegurar que el mapa se centre en la ubicación inicial después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isValidLocation(widget.initialCenter)) {
        _mapController.move(widget.initialCenter, 15);
      }
    });
  }

  // Helper to check if coordinates are valid
  bool _isValidLocation(LatLng location) {
    return location.latitude != 0.0 &&
        location.longitude != 0.0 &&
        location.latitude >= -90 &&
        location.latitude <= 90 &&
        location.longitude >= -180 &&
        location.longitude <= 180;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Asegurar que el mapa se centre en la ubicación inicial al menos una vez
    if (!_cameraCentered && mounted && _isValidLocation(widget.initialCenter)) {
      _mapController.move(widget.initialCenter, 15);
      _cameraCentered = true;
    }
  }

  @override
  void dispose() {
    _smoothTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MiniTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    try {
      if (kDebugMode) {
        print(
          '🗺️ MiniTrackingMap.didUpdateWidget => driver=${widget.driverLocation.latitude},${widget.driverLocation.longitude}',
        );
      }
    } catch (_) {}
    // Si recibimos una nueva ubicación del repartidor desde el padre (socket),
    // actualizamos el marcador y movemos la cámara si es la primera vez o si cambió significativamente.
    if (!widget.animateMock &&
        (oldWidget.driverLocation.latitude != widget.driverLocation.latitude ||
            oldWidget.driverLocation.longitude !=
                widget.driverLocation.longitude)) {
      setState(() {
        _animatedDriver = widget.driverLocation;
      });
      // Mover la cámara al repartidor cuando se actualiza su ubicación
      _mapController.move(widget.driverLocation, _mapController.camera.zoom);
      _cameraCentered = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _animatedDriver ?? widget.driverLocation;
    try {
      if (kDebugMode) {
        print(
          '🗺️ MiniTrackingMap.build => animatedDriver=${driver.latitude},${driver.longitude} cameraCenter=${_mapController.camera.center} zoom=${_mapController.camera.zoom}',
        );
      }
    } catch (_) {}

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
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
                    colors: [_kMapFallbackColor, _kMapFallbackColorDark],
                  ),
                ),
              ),
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.vallexpress.app',
                tileBuilder: (context, child, tile) {
                  // Añade fade-in suave cuando los tiles cargan
                  return AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  );
                },
                errorTileCallback: (tile, error, stackTrace) {
                  if (kDebugMode) {
                    print('❌ Error cargando tile de mapa: $error');
                  }
                },
              ),

              // Ruta simple (línea) cliente->vendedor->cliente (mock)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      widget.clientLocation,
                      widget.vendorLocation,
                      widget.clientLocation,
                    ],
                    strokeWidth: 4,
                    color: Colors.blue,
                  ),
                ],
              ),

              MarkerLayer(
                markers: [
                  if (_isValidLocation(widget.clientLocation))
                    _pin(
                      point: widget.clientLocation,
                      label: "C",
                      icon: Icons.home_rounded,
                      color: Colors.green,
                    ),
                  if (_isValidLocation(widget.vendorLocation))
                    _pin(
                      point: widget.vendorLocation,
                      label: "V",
                      icon: Icons.storefront_rounded,
                      color: Colors.red,
                    ),
                  if (_isValidLocation(driver))
                    _pin(
                      point: driver,
                      label: "R",
                      icon: Icons.delivery_dining_rounded,
                      color: Colors.orange,
                      isPrimary: true,
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Column(
              children: [
                if (widget.onRefresh != null) ...[
                  _iconButton(Icons.refresh, widget.onRefresh!),
                  const SizedBox(height: 8),
                ],
                _iconButton(Icons.add, () {
                  final z = _mapController.camera.zoom;
                  _mapController.move(_mapController.camera.center, z + 1);
                }),
                const SizedBox(height: 8),
                _iconButton(Icons.remove, () {
                  final z = _mapController.camera.zoom;
                  _mapController.move(_mapController.camera.center, z - 1);
                }),
              ],
            ),
            
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onPressed) {
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

  Marker _pin({
    required LatLng point,
    required String label,
    required IconData icon,
    required Color color,
    bool isPrimary = false,
  }) {
    return Marker(
      point: point,
      width: 54,
      height: 54,
      child: Container(
        decoration: BoxDecoration(
          color: isPrimary ? color : color.withOpacity(0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.25),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            size: 28,
            color: isPrimary ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
