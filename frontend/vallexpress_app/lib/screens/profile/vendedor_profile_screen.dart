import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:convert';
import '../../config/theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/vendedor_service.dart';

class VendedorProfileScreen extends StatefulWidget {
  const VendedorProfileScreen({super.key});

  @override
  State<VendedorProfileScreen> createState() => _VendedorProfileScreenState();
}

class _VendedorProfileScreenState extends State<VendedorProfileScreen> {
  late final TextEditingController _nombreNegocioController;
  late final TextEditingController _descripcionController;
  late final TextEditingController _categoriaController;
  late final TextEditingController _horaAperturaController;
  late final TextEditingController _horaCierreController;

  Map<String, dynamic>? _vendedorData;
  bool _isLoading = true;
  bool _isEditing = false;

  // Ubicación del vendedor
  double? _latitud;
  double? _longitud;
  bool _isEditingLocation = false;
  final MapController _mapController = MapController();
  LatLng? _tempLocation;

  @override
  void initState() {
    super.initState();

    _nombreNegocioController = TextEditingController();
    _descripcionController = TextEditingController();
    _categoriaController = TextEditingController();
    _horaAperturaController = TextEditingController();
    _horaCierreController = TextEditingController();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _nombreNegocioController.dispose();
    _descripcionController.dispose();
    _categoriaController.dispose();
    _horaAperturaController.dispose();
    _horaCierreController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ================= PERFIL =================

  Future<void> _cargarPerfil() async {
    try {
      final datos = await VendedorService.obtenerPerfilVendedor();

      if (!mounted) return;
      // Extraer coordenadas del vendedor
      final lat = datos['ubicacionLatitud'] ?? datos['latitud'] ?? datos['lat'];
      final lng =
          datos['ubicacionLongitud'] ?? datos['longitud'] ?? datos['lng'];

      setState(() {
        _vendedorData = datos;
        _nombreNegocioController.text =
            (datos['nombreNegocio'] ?? datos['nombre_negocio'] ?? '')
                .toString();
        _descripcionController.text = (datos['descripcion'] ?? '').toString();
        _categoriaController.text = (datos['categoria'] ?? '').toString();
        _horaAperturaController.text =
            (datos['horarioApertura'] ?? datos['horario_apertura'] ?? '')
                .toString();
        _horaCierreController.text =
            (datos['horarioCierre'] ?? datos['horario_cierre'] ?? '')
                .toString();
        _latitud = lat != null ? double.tryParse(lat.toString()) : null;
        _longitud = lng != null ? double.tryParse(lng.toString()) : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _mostrarError('Error al cargar perfil: $e');
    }
  }

  Future<void> _guardarCambios() async {
    if (_vendedorData == null) return;

    try {
      _mostrarCargando('Guardando cambios...');

      await VendedorService.actualizarPerfilVendedor(
        nombreNegocio: _nombreNegocioController.text.trim(),
        categoria: _categoriaController.text.trim(),
        descripcion: _descripcionController.text.trim(),
        direccion: (_vendedorData!['direccion'] ?? '').toString(),
        ciudad: (_vendedorData!['ciudad'] ?? '').toString(),
        telefono: (_vendedorData!['telefono'] ?? '').toString(),
        horarioApertura: _horaAperturaController.text.trim(),
        horarioCierre: _horaCierreController.text.trim(),
        diaDescanso:
            (_vendedorData!['diaDescanso'] ??
                    (_vendedorData!['dia_descanso'] ?? 'Lunes'))
                .toString(),
      );

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _isEditing = false;
        _vendedorData!['nombre_negocio'] = _nombreNegocioController.text.trim();
        _vendedorData!['descripcion'] = _descripcionController.text.trim();
        _vendedorData!['categoria'] = _categoriaController.text.trim();
        _vendedorData!['horario_apertura'] = _horaAperturaController.text
            .trim();
        _vendedorData!['horario_cierre'] = _horaCierreController.text.trim();
      });

      _mostrarExito('Perfil actualizado correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al guardar: $e');
    }
  }

  // ================= LOGO Y BANNER =================

  Future<void> _subirLogo() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      _mostrarCargando('Subiendo foto...');

      final base64 = await VendedorService.xfileToBase64(image);
      await VendedorService.actualizarLogoBase64(base64);

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _vendedorData!['logo'] = base64;
      });

      _mostrarExito('Foto actualizada correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al subir foto: $e');
    }
  }

  Future<void> _subirBanner() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      _mostrarCargando('Subiendo banner...');

      final base64 = await VendedorService.xfileToBase64(image);
      await VendedorService.actualizarBannerBase64(base64);

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _vendedorData!['banner'] = base64;
      });

      _mostrarExito('Banner actualizado correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al subir banner: $e');
    }
  }

  // ================= UBICACIÓN =================

  void _startEditingLocation() {
    setState(() {
      _isEditingLocation = true;
      // Usar ubicación guardada o centro por defecto (Yantzaza)
      _tempLocation = LatLng(_latitud ?? -3.8320, _longitud ?? -78.7590);
    });
  }

  void _cancelEditingLocation() {
    setState(() {
      _isEditingLocation = false;
      _tempLocation = null;
    });
  }

  Future<void> _saveLocation() async {
    if (_tempLocation == null) return;

    try {
      _mostrarCargando('Guardando ubicación...');

      await VendedorService.actualizarUbicacion(
        latitud: _tempLocation!.latitude,
        longitud: _tempLocation!.longitude,
      );

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _latitud = _tempLocation!.latitude;
        _longitud = _tempLocation!.longitude;
        _isEditingLocation = false;
        _tempLocation = null;
        if (_vendedorData != null) {
          _vendedorData!['ubicacionLatitud'] = _latitud;
          _vendedorData!['ubicacionLongitud'] = _longitud;
        }
      });

      _mostrarExito('Ubicación actualizada correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al guardar ubicación: $e');
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    if (_isEditingLocation) {
      setState(() {
        _tempLocation = latlng;
      });
    }
  }

  // ================= UI HELPERS =================

  void _mostrarCargando(String mensaje) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
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

  String _obtenerIniciales() {
    final usuario = _vendedorData?['usuario'];
    final nombreUsuario = usuario != null ? (usuario['nombre'] ?? '') : '';
    final negocio = (_vendedorData?['nombre_negocio'] ?? '').toString();
    final source = nombreUsuario.toString().isNotEmpty
        ? nombreUsuario.toString()
        : negocio;
    return source.isNotEmpty ? source.substring(0, 1).toUpperCase() : 'V';
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_vendedorData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mi Negocio'),
          backgroundColor: AppTheme.primaryColor,
        ),
        body: const Center(child: Text('No se pudo cargar el perfil')),
      );
    }

    final nombreNegocio = (_vendedorData!['nombre_negocio'] ?? '').toString();
    final calificacion = (_vendedorData!['calificacion_promedio'] ?? 0.0)
        .toString();
    final logo = (_vendedorData!['logo'] ?? '').toString();
    final banner = (_vendedorData!['banner'] ?? '').toString();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Mi Negocio'),
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.vendedorColor.withOpacity(0.3),
                AppTheme.cardColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
              });
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            // BANNER con gradiente
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: banner.isEmpty
                    ? LinearGradient(
                        colors: [
                          AppTheme.vendedorColor.withOpacity(0.4),
                          AppTheme.vendedorColor.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: banner.isEmpty ? null : AppTheme.cardColor,
                image: banner.isNotEmpty
                    ? DecorationImage(
                        image: banner.startsWith('http')
                            ? NetworkImage(banner)
                            : MemoryImage(base64Decode(banner))
                                  as ImageProvider,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: banner.isEmpty
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.vendedorColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.store,
                          size: 60,
                          color: AppTheme.vendedorColor,
                        ),
                      ),
                    )
                  : null,
            ),

            Transform.translate(
              offset: const Offset(0, -40),
              child: Column(
                children: [
                  // LOGO con glow
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.vendedorColor.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: logo.isNotEmpty
                            ? CircleAvatar(
                                radius: 60,
                                backgroundImage: logo.startsWith('http')
                                    ? NetworkImage(logo)
                                    : MemoryImage(base64Decode(logo))
                                          as ImageProvider,
                              )
                            : CircleAvatar(
                                radius: 60,
                                backgroundColor: AppTheme.vendedorColor,
                                child: Text(
                                  _obtenerIniciales(),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _subirLogo,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.vendedorColor,
                                  AppTheme.vendedorColor.withOpacity(0.8),
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.vendedorColor.withOpacity(
                                    0.4,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.transparent,
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Mostrar el nombre del usuario si viene en la relación, si no, el nombre del negocio
                  Text(
                    (_vendedorData?['usuario'] != null
                            ? '${_vendedorData!['usuario']['nombre'] ?? ''} ${_vendedorData!['usuario']['apellido'] ?? ''}'
                            : nombreNegocio)
                        .trim(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        calificacion,
                        style: const TextStyle(
                          color: AppTheme.textSecondaryColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.vendedorColor.withOpacity(0.2),
                          AppTheme.vendedorColor.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.vendedorColor.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'VENDEDOR',
                      style: TextStyle(
                        color: AppTheme.vendedorColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // FORMULARIO
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _editableTile('Nombre del Negocio', _nombreNegocioController),
                  const SizedBox(height: 12),
                  _editableTile(
                    'Descripción',
                    _descripcionController,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _editableTile('Categoría', _categoriaController),
                  const SizedBox(height: 12),
                  _editableTile('Hora Apertura', _horaAperturaController),
                  const SizedBox(height: 12),
                  _editableTile('Hora Cierre', _horaCierreController),
                  const SizedBox(height: 24),
                  // ===== Ubicación del negocio =====
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ubicación del negocio',
                        style: TextStyle(
                          color: AppTheme.textPrimaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      if (!_isEditingLocation)
                        TextButton.icon(
                          onPressed: _startEditingLocation,
                          icon: const Icon(Icons.edit_location, size: 18),
                          label: const Text('Editar'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                          ),
                        )
                      else
                        Row(
                          children: [
                            TextButton(
                              onPressed: _cancelEditingLocation,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: _saveLocation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                              ),
                              child: const Text(
                                'Guardar',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      SizedBox(
                        height: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter:
                                  _isEditingLocation && _tempLocation != null
                                  ? _tempLocation!
                                  : (_latitud != null && _longitud != null)
                                  ? LatLng(_latitud!, _longitud!)
                                  : const LatLng(-3.8320, -78.7590),
                              initialZoom: 15,
                              onTap: _onMapTap,
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
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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

                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point:
                                        _isEditingLocation &&
                                            _tempLocation != null
                                        ? _tempLocation!
                                        : (_latitud != null &&
                                              _longitud != null)
                                        ? LatLng(_latitud!, _longitud!)
                                        : const LatLng(-3.8320, -78.7590),
                                    width: 54,
                                    height: 54,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _isEditingLocation
                                            ? Colors.blue
                                            : AppTheme.vendedorColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.3,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Icon(
                                          _isEditingLocation
                                              ? Icons.edit_location_alt
                                              : Icons.storefront_rounded,
                                          size: 28,
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
                      // Botones de zoom
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'zoom_in',
                              onPressed: () {
                                final currentZoom = _mapController.camera.zoom;
                                _mapController.move(
                                  _mapController.camera.center,
                                  currentZoom + 1,
                                );
                              },
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.add, color: Colors.black),
                            ),
                            const SizedBox(height: 4),
                            FloatingActionButton.small(
                              heroTag: 'zoom_out',
                              onPressed: () {
                                final currentZoom = _mapController.camera.zoom;
                                _mapController.move(
                                  _mapController.camera.center,
                                  currentZoom - 1,
                                );
                              },
                              backgroundColor: Colors.white,
                              child: const Icon(
                                Icons.remove,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_isEditingLocation) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.vendedorColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.vendedorColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppTheme.vendedorColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Toca en el mapa para mover la ubicación. Usa +/- para zoom.',
                              style: TextStyle(
                                color: AppTheme.vendedorColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editableTile(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.cardColor, AppTheme.cardColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isEditing
              ? AppTheme.vendedorColor.withOpacity(0.5)
              : AppTheme.borderColor.withOpacity(0.2),
          width: _isEditing ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getIconForLabel(label),
                size: 16,
                color: AppTheme.vendedorColor,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textSecondaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: _isEditing,
            maxLines: maxLines,
            style: TextStyle(
              color: AppTheme.textPrimaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '-',
              hintStyle: TextStyle(
                color: AppTheme.textSecondaryColor.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForLabel(String label) {
    switch (label) {
      case 'Nombre del Negocio':
        return Icons.store_outlined;
      case 'Descripción':
        return Icons.description_outlined;
      case 'Categoría':
        return Icons.category_outlined;
      case 'Hora Apertura':
        return Icons.access_time_outlined;
      case 'Hora Cierre':
        return Icons.access_time_filled_outlined;
      default:
        return Icons.info_outline;
    }
  }
}
