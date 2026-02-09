import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/repartidor_service.dart';
import '../../widgets/gradient_button.dart';

class RepartidorProfileScreen extends StatefulWidget {
  const RepartidorProfileScreen({super.key});

  @override
  State<RepartidorProfileScreen> createState() =>
      _RepartidorProfileScreenState();
}

class _RepartidorProfileScreenState extends State<RepartidorProfileScreen> {
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
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _mostrarError('Error al cargar perfil: $e');
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

    final nombre = (_repartidorData!['nombre'] ?? 'Repartidor').toString();
    final estado = (_repartidorData!['estado'] ?? 'disponible').toString();
    final calificacion = (_repartidorData!['calificacion_notificacio'] ?? 0)
        .toString();
    final entregas = (_repartidorData!['pedidos_completados'] ?? 0).toString();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppTheme.repartidorColor, AppTheme.accentColor],
          ).createShader(bounds),
          child: const Text(
            'Mi Perfil',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.repartidorColor),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.repartidorColor.withOpacity(0.2),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TARJETA PRINCIPAL con estilo racing
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.cardColor,
                    AppTheme.cardColor.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.repartidorColor.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.repartidorColor.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar con glow cian
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_repartidorData!['disponible'] ?? false)
                              ? AppTheme.repartidorColor.withOpacity(0.6)
                              : Colors.grey.withOpacity(0.4),
                          blurRadius: 25,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: (_repartidorData!['disponible'] ?? false)
                          ? AppTheme.repartidorColor
                          : Colors.grey,
                      child: Icon(
                        estado == 'disponible'
                            ? Icons.two_wheeler
                            : Icons.pause_circle,
                        size: 45,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  // Nombre con estilo
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Badge de repartidor
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.repartidorColor.withOpacity(0.2),
                          AppTheme.repartidorColor.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.repartidorColor.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'REPARTIDOR',
                      style: TextStyle(
                        color: AppTheme.repartidorColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Toggle de disponibilidad estilizado
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          (_repartidorData!['disponible'] ?? false)
                              ? AppTheme.repartidorColor.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.1),
                          AppTheme.cardColor.withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (_repartidorData!['disponible'] ?? false)
                            ? AppTheme.repartidorColor.withOpacity(0.4)
                            : Colors.grey.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (_repartidorData!['disponible'] ?? false)
                                    ? AppTheme.repartidorColor.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                (_repartidorData!['disponible'] ?? false)
                                    ? Icons.check_circle
                                    : Icons.do_not_disturb,
                                color: (_repartidorData!['disponible'] ?? false)
                                    ? AppTheme.repartidorColor
                                    : Colors.grey,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Disponible',
                                  style: TextStyle(
                                    color: AppTheme.textPrimaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (_repartidorData!['disponible'] ?? false)
                                      ? 'Recibiendo pedidos'
                                      : 'No disponible',
                                  style: TextStyle(
                                    color: AppTheme.textSecondaryColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: _repartidorData!['disponible'] ?? false,
                          onChanged: _cambiarDisponibilidad,
                          activeThumbColor: AppTheme.repartidorColor,
                          activeTrackColor: AppTheme.repartidorColor
                              .withOpacity(0.3),
                          inactiveThumbColor: Colors.grey,
                          inactiveTrackColor: Colors.grey.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // Stats con estilo racing
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard(
                        icon: Icons.star_rounded,
                        value: calificacion,
                        label: 'Calificación',
                        color: Colors.amber,
                      ),
                      Container(
                        height: 50,
                        width: 1,
                        color: AppTheme.borderColor.withOpacity(0.3),
                      ),
                      _buildStatCard(
                        icon: Icons.check_circle_rounded,
                        value: entregas,
                        label: 'Entregas',
                        color: AppTheme.repartidorColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // VEHÍCULO con estilo
            _buildSectionTitle('🛵 Información del Vehículo'),
            const SizedBox(height: 16),
            _buildStyledInput(
              'Vehículo',
              _vehiculoController,
              _isEditing,
              Icons.two_wheeler,
            ),
            const SizedBox(height: 16),
            _buildStyledInput(
              'Placa',
              _placaController,
              _isEditing,
              Icons.confirmation_number,
            ),
            const SizedBox(height: 32),

            // BOTÓN con gradiente
            GradientButton(
              text: _isEditing ? 'Guardar Cambios' : 'Editar Perfil',
              onPressed: _isEditing
                  ? _guardarCambios
                  : () {
                      setState(() => _isEditing = true);
                    },
              gradientColors: [AppTheme.repartidorColor, AppTheme.accentColor],
              icon: _isEditing ? Icons.save : Icons.edit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: AppTheme.repartidorColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: AppTheme.textPrimaryColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
        ),
      ],
    );
  }

  Widget _buildStyledInput(
    String label,
    TextEditingController controller,
    bool isEditing,
    IconData icon,
  ) {
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
              ? AppTheme.repartidorColor.withOpacity(0.5)
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
      child: isEditing
          ? TextField(
              controller: controller,
              style: const TextStyle(
                color: AppTheme.textPrimaryColor,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: AppTheme.repartidorColor),
                prefixIcon: Icon(icon, color: AppTheme.repartidorColor),
                border: InputBorder.none,
                isDense: true,
              ),
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.repartidorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.repartidorColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
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
                          fontWeight: FontWeight.w600,
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
