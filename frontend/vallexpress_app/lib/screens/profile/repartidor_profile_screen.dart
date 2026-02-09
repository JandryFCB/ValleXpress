import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/repartidor_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

class RepartidorProfileScreen extends StatefulWidget {
  const RepartidorProfileScreen({super.key});

  @override
  State<RepartidorProfileScreen> createState() =>
      _RepartidorProfileScreenState();
}

class _RepartidorProfileScreenState extends State<RepartidorProfileScreen> {
  String? _fotoUrl;
  late final TextEditingController _vehiculoController;
  late final TextEditingController _placaController;

  Map<String, dynamic>? _repartidorData;
  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _vehiculoController = TextEditingController();
    _placaController = TextEditingController();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _vehiculoController.dispose();
    _placaController.dispose();
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    try {
      final datos = await RepartidorService.obtenerPerfilRepartidor();
      if (!mounted) return;
      setState(() {
        _repartidorData = datos;
        _vehiculoController.text = (datos['vehiculo'] ?? '').toString();
        _placaController.text = (datos['placa'] ?? '').toString();
        _fotoUrl = (datos['foto'] ?? '').toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _mostrarError('Error al cargar perfil: $e');
    }
  }

  // ================= FOTO =================
  Future<void> _subirFoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;
    _mostrarCargando('Subiendo foto...');
    try {
      await RepartidorService.subirFotoPerfil(image);
      if (!mounted) return;
      Navigator.pop(context);
      // Recargar el perfil completo para asegurar que la foto se muestre
      await _cargarPerfil();
      _mostrarExito('Foto actualizada correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al subir foto: $e');
    }
  }

  Future<void> _guardarCambios() async {
    if (_repartidorData == null) return;

    try {
      _mostrarCargando('Guardando cambios...');

      await RepartidorService.actualizarPerfilRepartidor(
        estado: (_repartidorData!['estado'] ?? 'disponible').toString(),
        vehiculo: _vehiculoController.text.trim(),
        placa: _placaController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _isEditing = false;
        _repartidorData!['vehiculo'] = _vehiculoController.text.trim();
        _repartidorData!['placa'] = _placaController.text.trim();
      });

      _mostrarExito('Perfil actualizado correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error al guardar: $e');
    }
  }

  Future<void> _cambiarDisponibilidad(bool value) async {
    try {
      await RepartidorService.cambiarDisponibilidad(value);

      if (!mounted) return;
      setState(() {
        _repartidorData!['disponible'] = value;
      });

      _mostrarExito(
        value
            ? 'Ahora estás disponible para recibir pedidos'
            : 'Ya no recibirás pedidos nuevos',
      );
    } catch (e) {
      _mostrarError('Error al cambiar disponibilidad: $e');
    }
  }

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_repartidorData == null) {
      return const Scaffold(
        body: Center(child: Text('No se pudo cargar el perfil')),
      );
    }

    // Nombre del usuario si viene en la relación 'usuario', sino buscar nombre en repartidor
    final usuario = _repartidorData!['usuario'];
    final nombre = usuario != null
        ? ("${usuario['nombre'] ?? ''} ${usuario['apellido'] ?? ''}").trim()
        : (_repartidorData!['nombre'] ?? 'Repartidor').toString();
    final estado =
        (_repartidorData!['disponible'] != null
                ? ((_repartidorData!['disponible'] == true ||
                          _repartidorData!['disponible'].toString() == 'true')
                      ? 'disponible'
                      : 'no disponible')
                : (_repartidorData!['estado'] ?? 'disponible'))
            .toString();
    // calificacion_promedio vs calificacion_notificacio
    final calificacion =
        (_repartidorData!['calificacion_promedio'] ??
                _repartidorData!['calificacion_notificacio'] ??
                0)
            .toString();
    final entregas = (_repartidorData!['pedidos_completados'] ?? 0).toString();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        title: const Text('Mi Perfil'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TARJETA PRINCIPAL
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.borderColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      _fotoUrl != null && _fotoUrl!.isNotEmpty
                          ? CircleAvatar(
                              radius: 50,
                              backgroundImage: _fotoUrl!.startsWith('http')
                                  ? NetworkImage(_fotoUrl!)
                                  : MemoryImage(base64Decode(_fotoUrl!))
                                        as ImageProvider,
                            )
                          : CircleAvatar(
                              radius: 50,
                              backgroundColor: AppTheme.primaryColor,
                              child: const Icon(
                                Icons.motorcycle,
                                size: 50,
                                color: Colors.white,
                              ),
                            ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _subirFoto,
                          child: const CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.primaryColor,
                            child: Icon(
                              Icons.camera_alt,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nombre.isNotEmpty ? nombre : 'Repartidor',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  // Toggle de disponibilidad
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.borderColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Disponible para entregas',
                              style: TextStyle(
                                color: AppTheme.textPrimaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (_repartidorData!['disponible'] ?? false)
                                  ? 'Activo - Puedes recibir pedidos'
                                  : 'Inactivo - No recibirás pedidos',
                              style: TextStyle(
                                color: AppTheme.textSecondaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _repartidorData!['disponible'] ?? false,
                          onChanged: _cambiarDisponibilidad,
                          activeThumbColor: AppTheme.primaryColor,
                          activeTrackColor: AppTheme.primaryColor.withOpacity(
                            0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(height: 4),
                          Text(
                            calificacion,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Text(
                            'Calificación',
                            style: TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entregas,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Text(
                            'Entregas',
                            style: TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // VEHÍCULO
            _buildSectionTitle('Información del Vehículo'),
            const SizedBox(height: 12),
            _buildInputField('Vehículo', _vehiculoController, _isEditing),
            const SizedBox(height: 12),
            _buildInputField('Placa', _placaController, _isEditing),
            const SizedBox(height: 24),

            // BOTÓN
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isEditing
                    ? _guardarCambios
                    : () {
                        setState(() => _isEditing = true);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _isEditing ? 'Guardar cambios' : 'Editar perfil',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimaryColor,
      ),
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    bool isEditing,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.borderColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: isEditing
          ? TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                border: InputBorder.none,
                isDense: true,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.text.isEmpty ? '-' : controller.text,
                  style: const TextStyle(
                    color: AppTheme.textPrimaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
    );
  }
}
