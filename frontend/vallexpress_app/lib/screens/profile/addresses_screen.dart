import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/theme.dart';
import '../../services/address_service.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  bool _loading = true;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await AddressService.listar();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _getCurrentLocation(
    TextEditingController latCtrl,
    TextEditingController lngCtrl,
    StateSetter setDialogState,
  ) async {
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permiso de ubicación denegado permanentemente. Actívalo en configuración',
            ),
          ),
        );
        return;
      }

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Obtener ubicación
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Cerrar indicador de carga
      Navigator.pop(context);

      // Actualizar campos
      setDialogState(() {
        latCtrl.text = position.latitude.toString();
        lngCtrl.text = position.longitude.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ubicación obtenida: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al obtener ubicación: $e')));
    }
  }

  Future<void> _createOrEdit({Map<String, dynamic>? current}) async {
    // Navegar a pantalla de mapa en lugar de usar dialog
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AddressMapScreen(
          initialLocation: current != null
              ? LatLng(
                  double.tryParse((current['latitud'] ?? '').toString()) ??
                      -3.8320,
                  double.tryParse((current['longitud'] ?? '').toString()) ??
                      -78.7590,
                )
              : null,
          initialNombre: (current?['nombre'] ?? '').toString(),
          initialDireccion: (current?['direccion'] ?? '').toString(),
          esPredeterminada:
              (current?['esPredeterminada'] ??
                  current?['es_predeterminada'] ??
                  false) ==
              true,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      try {
        if (current == null) {
          await AddressService.crear(
            nombre: result['nombre'],
            direccion: result['direccion'],
            latitud: result['latitud'],
            longitud: result['longitud'],
            esPredeterminada: result['esPredeterminada'],
          );
        } else {
          await AddressService.actualizar(
            (current['id'] ?? '').toString(),
            nombre: result['nombre'],
            direccion: result['direccion'],
            latitud: result['latitud'],
            longitud: result['longitud'],
            esPredeterminada: result['esPredeterminada'],
          );
        }
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  Future<void> _setDefault(Map<String, dynamic> item) async {
    try {
      await AddressService.marcarPredeterminada((item['id'] ?? '').toString());
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    try {
      await AddressService.eliminar((item['id'] ?? '').toString());
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Mis direcciones'),
        backgroundColor: AppTheme.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Recargar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createOrEdit(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Text(
                'No tienes direcciones registradas',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, i) {
                final it = _items[i];
                final nombre = (it['nombre'] ?? '').toString();
                final direccion = (it['direccion'] ?? '').toString();
                final lat = double.tryParse((it['latitud'] ?? '').toString());
                final lng = double.tryParse((it['longitud'] ?? '').toString());
                final pred =
                    (it['esPredeterminada'] ??
                        it['es_predeterminada'] ??
                        false) ==
                    true;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: pred
                          ? Colors.amber
                          : AppTheme.borderColor.withOpacity(0.3),
                      width: pred ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            pred ? Icons.star : Icons.place,
                            color: pred ? Colors.amber : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nombre.isNotEmpty ? nombre : 'Dirección',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit, color: Colors.white70),
                            onPressed: () => _createOrEdit(current: it),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _delete(it),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        direccion,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: (lat != null && lng != null)
                                  ? LatLng(lat, lng)
                                  : const LatLng(0, 0),
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
                                    colors: [
                                      Color(0xFFE0E0E0),
                                      Color(0xFFBDBDBD),
                                    ],
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

                              if (lat != null && lng != null)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: LatLng(lat, lng),
                                      width: 46,
                                      height: 46,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF0AB6FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.place,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!pred)
                            TextButton.icon(
                              onPressed: () => _setDefault(it),
                              icon: const Icon(
                                Icons.star_border,
                                color: Colors.amber,
                              ),
                              label: const Text('Marcar predeterminada'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _items.length,
            ),
    );
  }
}

// ==================== PANTALLA DE MAPA PARA SELECCIONAR UBICACIÓN ====================

class _AddressMapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final String initialNombre;
  final String initialDireccion;
  final bool esPredeterminada;

  const _AddressMapScreen({
    this.initialLocation,
    this.initialNombre = '',
    this.initialDireccion = '',
    this.esPredeterminada = false,
  });

  @override
  State<_AddressMapScreen> createState() => _AddressMapScreenState();
}

class _AddressMapScreenState extends State<_AddressMapScreen> {
  late final MapController _mapController;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _direccionCtrl;
  late LatLng _selectedLocation;
  bool _esPredeterminada = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _nombreCtrl = TextEditingController(text: widget.initialNombre);
    _direccionCtrl = TextEditingController(text: widget.initialDireccion);
    _selectedLocation =
        widget.initialLocation ?? const LatLng(-3.8320, -78.7590);
    _esPredeterminada = widget.esPredeterminada;
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permiso denegado permanentemente. Actívalo en configuración',
            ),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
      });

      _mapController.move(_selectedLocation, 16);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ubicación: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      _selectedLocation = latlng;
    });
  }

  void _saveAndReturn() {
    if (_direccionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una dirección/referencia')),
      );
      return;
    }

    Navigator.pop(context, {
      'nombre': _nombreCtrl.text.trim().isEmpty
          ? null
          : _nombreCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'latitud': _selectedLocation.latitude,
      'longitud': _selectedLocation.longitude,
      'esPredeterminada': _esPredeterminada,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Seleccionar ubicación'),
        backgroundColor: AppTheme.primaryColor,
        actions: [
          if (_isGettingLocation)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _getCurrentLocation,
              tooltip: 'Mi ubicación',
            ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveAndReturn,
            tooltip: 'Guardar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Campos de texto
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nombreCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nombre (ej: Casa, Trabajo)',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    prefixIcon: const Icon(
                      Icons.label_outline,
                      color: Colors.white70,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _direccionCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Dirección / Referencia',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    prefixIcon: const Icon(Icons.notes, color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: _esPredeterminada,
                      onChanged: (v) => setState(() {
                        _esPredeterminada = v ?? false;
                      }),
                    ),
                    const Text(
                      'Marcar como predeterminada',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Mapa
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation,
                    initialZoom: 15,
                    onTap: _onMapTap,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.vallexpress.app',
                      maxZoom: 19,
                    ),

                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedLocation,
                          width: 50,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.clienteColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.clienteColor.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Botones de zoom
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom_in_map',
                        onPressed: () {
                          final z = _mapController.camera.zoom;
                          _mapController.move(
                            _mapController.camera.center,
                            z + 1,
                          );
                        },
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.add, color: Colors.black),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoom_out_map',
                        onPressed: () {
                          final z = _mapController.camera.zoom;
                          _mapController.move(
                            _mapController.camera.center,
                            z - 1,
                          );
                        },
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.remove, color: Colors.black),
                      ),
                    ],
                  ),
                ),
                // Indicador de tocar
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.clienteColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Toca el mapa',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
