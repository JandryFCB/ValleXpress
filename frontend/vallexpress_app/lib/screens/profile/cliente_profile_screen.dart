import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:convert';
import '../../config/theme.dart';
import '../../config/constants.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/profile_service.dart';
import '../../services/address_service.dart';
import './addresses_screen.dart';
import '../../widgets/gradient_button.dart';

class ClienteProfileScreen extends StatefulWidget {
  const ClienteProfileScreen({super.key});

  @override
  State<ClienteProfileScreen> createState() => _ClienteProfileScreenState();
}

class _ClienteProfileScreenState extends State<ClienteProfileScreen> {
  late final TextEditingController _telefonoController;

  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _direccionPredeterminada;
  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _telefonoController = TextEditingController();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _telefonoController.dispose();
    super.dispose();
  }

  // ================= PERFIL =================

  Future<void> _cargarPerfil() async {
    try {
      // 🚀 OPTIMIZACIÓN: Cargar en paralelo, no secuencial
      final results = await Future.wait([
        ProfileService.obtenerPerfil(),
        AddressService.predeterminada().catchError((_) => null),
      ]);

      final datos = results[0] as Map<String, dynamic>;
      final direccion = results[1] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _userData = datos;
        _direccionPredeterminada = direccion;
        _telefonoController.text = (datos['telefono'] ?? '').toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _mostrarError('Error al cargar perfil: $e');
    }
  }

  Future<void> _guardarCambios() async {
    if (_userData == null) return;

    try {
      _mostrarCargando('Guardando cambios...');

      await ProfileService.actualizarPerfil(
        nombre: (_userData!['nombre'] ?? '').toString(),
        apellido: (_userData!['apellido'] ?? '').toString(),
        telefono: _telefonoController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context); // cerrar loading

      setState(() {
        _isEditing = false;
        _userData!['telefono'] = _telefonoController.text.trim();
      });

      _mostrarExito('Perfil actualizado correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al guardar: $e');
    }
  }

  // ================= FOTO =================

  Future<void> _subirFoto() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      _mostrarCargando('Subiendo foto...');

      final base64 = await ProfileService.xfileToBase64(image);
      await ProfileService.actualizarFotoPerfilBase64(base64);

      if (!mounted) return;
      Navigator.pop(context); // cerrar loading

      setState(() {
        _userData!['fotoPerfil'] = base64;
      });

      _mostrarExito('Foto actualizada correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al subir foto: $e');
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
    final nombre = (_userData?['nombre'] ?? '').toString();
    final apellido = (_userData?['apellido'] ?? '').toString();

    final n = nombre.isNotEmpty ? nombre[0] : '';
    final a = apellido.isNotEmpty ? apellido[0] : '';
    return (n + a).toUpperCase();
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mi Perfil'),
          backgroundColor: AppTheme.primaryColor,
        ),
        body: const Center(child: Text('No se pudo cargar el perfil')),
      );
    }

    final nombre = (_userData!['nombre'] ?? '').toString();
    final apellido = (_userData!['apellido'] ?? '').toString();
    final email = (_userData!['email'] ?? '').toString();
    final cedula = (_userData!['cedula'] ?? '').toString();

    final foto = (_userData!['fotoPerfil'] ?? _userData!['foto_perfil'] ?? '')
        .toString();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppTheme.clienteColor, AppTheme.accentColor],
          ).createShader(bounds),
          child: const Text(
            'Mi Perfil',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.clienteColor),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.clienteColor.withOpacity(0.2),
                AppTheme.cardColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // AVATAR con glow verde
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.clienteColor.withOpacity(0.4),
                    blurRadius: 25,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  foto.isNotEmpty
                      ? CircleAvatar(
                          radius: 65,
                          backgroundImage: foto.startsWith('http')
                              ? NetworkImage(foto)
                              : MemoryImage(base64Decode(foto))
                                    as ImageProvider,
                        )
                      : CircleAvatar(
                          radius: 65,
                          backgroundColor: AppTheme.clienteColor,
                          child: Text(
                            _obtenerIniciales(),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _subirFoto,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.clienteColor,
                              AppTheme.clienteColor.withOpacity(0.8),
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.clienteColor.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.transparent,
                          child: Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text(
              '$nombre $apellido',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor,
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.clienteColor.withOpacity(0.2),
                    AppTheme.clienteColor.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.clienteColor.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Text(
                'CLIENTE',
                style: TextStyle(
                  color: AppTheme.clienteColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // INFO con estilo
            _buildInfoCard('Email', email, Icons.email_outlined, false),
            const SizedBox(height: 16),
            _buildInfoCard('Cédula', cedula, Icons.credit_card_outlined, false),
            const SizedBox(height: 16),
            _buildInfoCard(
              'Teléfono',
              _telefonoController.text,
              Icons.phone_outlined,
              _isEditing,
              controller: _telefonoController,
            ),

            const SizedBox(height: 32),

            GradientButton(
              text: _isEditing ? 'Guardar Cambios' : 'Editar Perfil',
              onPressed: _isEditing
                  ? _guardarCambios
                  : () => setState(() => _isEditing = true),
              gradientColors: [AppTheme.clienteColor, AppTheme.accentColor],
              icon: _isEditing ? Icons.save : Icons.edit,
            ),

            const SizedBox(height: 16),

            // Botón de direcciones
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.cardColor,
                    AppTheme.cardColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.clienteColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddressesScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: AppTheme.clienteColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Gestionar direcciones',
                          style: TextStyle(
                            color: AppTheme.clienteColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ===== Ubicación del cliente =====
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.clienteColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '📍 Ubicación',
                  style: TextStyle(
                    color: AppTheme.textPrimaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.clienteColor.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 220,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                        (_direccionPredeterminada?['latitud'] as num?)
                                ?.toDouble() ??
                            AppConstants.clientLat,
                        (_direccionPredeterminada?['longitud'] as num?)
                                ?.toDouble() ??
                            AppConstants.clientLng,
                      ),
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
                            point: LatLng(
                              (_direccionPredeterminada?['latitud'] as num?)
                                      ?.toDouble() ??
                                  AppConstants.clientLat,
                              (_direccionPredeterminada?['longitud'] as num?)
                                      ?.toDouble() ??
                                  AppConstants.clientLng,
                            ),
                            width: 60,
                            height: 60,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.clienteColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.clienteColor.withOpacity(
                                      0.5,
                                    ),
                                    blurRadius: 15,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.home_rounded,
                                  size: 30,
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
            ),

            if (_direccionPredeterminada != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.clienteColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.clienteColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: AppTheme.clienteColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _direccionPredeterminada!['direccion'] ??
                            'Dirección guardada',
                        style: TextStyle(
                          color: AppTheme.textPrimaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    IconData icon,
    bool isEditing, {
    TextEditingController? controller,
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
          color: isEditing
              ? AppTheme.clienteColor.withOpacity(0.5)
              : AppTheme.borderColor.withOpacity(0.2),
          width: isEditing ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.clienteColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.clienteColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                isEditing && controller != null
                    ? TextField(
                        controller: controller,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(
                          color: AppTheme.textPrimaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '-',
                        ),
                      )
                    : Text(
                        value.isEmpty ? '-' : value,
                        style: const TextStyle(
                          color: AppTheme.textPrimaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
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
