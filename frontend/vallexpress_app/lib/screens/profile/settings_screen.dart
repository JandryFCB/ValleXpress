import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/providers/auth_provider.dart';
import 'package:vallexpress_app/services/profile_service.dart';
import 'package:vallexpress_app/widgets/terms_and_conditions_modal.dart';
import 'package:vallexpress_app/screens/profile/profile_router.dart'; // ✅ NUEVO

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificacionesPedidos = true;
  bool _notificacionesPromo = true;
  bool _notificacionesProductos = false;
  bool _notificacionesPush = true;
  bool _notificacionesEmail = true;
  bool _notificacionesSMS = false;

  late final TextEditingController _passwordActualController;
  late final TextEditingController _passwordNuevaController;
  late final TextEditingController _confirmarPasswordController;

  final GlobalKey<FormState> _passwordFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _passwordActualController = TextEditingController();
    _passwordNuevaController = TextEditingController();
    _confirmarPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordActualController.dispose();
    _passwordNuevaController.dispose();
    _confirmarPasswordController.dispose();
    super.dispose();
  }

  // ================== NAVEGACIÓN ==================

  void _navegarAPerfil() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileRouter()),
    );
  }

  // ================== PASSWORD ==================

  Future<void> _cambiarContrasena() async {
    final actual = _passwordActualController.text.trim();
    final nueva = _passwordNuevaController.text.trim();
    final confirmar = _confirmarPasswordController.text.trim();

    if (actual.isEmpty || nueva.isEmpty || confirmar.isEmpty) {
      _mostrarError('Todos los campos son requeridos');
      return;
    }

    try {
      _mostrarCargando('Actualizando contraseña...');

      await ProfileService.cambiarContrasena(
        passwordActual: actual,
        passwordNueva: nueva,
        confirmarPassword: confirmar,
      );

      if (!mounted) return;

      Navigator.pop(context); // cerrar loading

      _passwordActualController.clear();
      _passwordNuevaController.clear();
      _confirmarPasswordController.clear();

      Navigator.pop(context); // cerrar modal
      _mostrarExito('Contraseña actualizada correctamente');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarError('Error: $e');
    }
  }

  void _mostrarModalCambiarContrasena() {
    bool verActual = false;
    bool verNueva = false;
    bool verConfirmar = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 16,
              ),
              child: Form(
                key: _passwordFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cambiar Contraseña',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimaryColor,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // CONTRASEÑA ACTUAL
                    TextFormField(
                      controller: _passwordActualController,
                      obscureText: !verActual,
                      style: const TextStyle(color: AppTheme.textPrimaryColor),
                      decoration: InputDecoration(
                        hintText: 'Contraseña Actual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          splashRadius: 20,
                          onPressed: () => modalSetState(() {
                            verActual = !verActual;
                          }),
                          icon: Icon(
                            verActual ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'Ingresa tu contraseña actual';
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),

                    const SizedBox(height: 16),

                    // NUEVA CONTRASEÑA
                    TextFormField(
                      controller: _passwordNuevaController,
                      obscureText: !verNueva,
                      style: const TextStyle(color: AppTheme.textPrimaryColor),
                      decoration: InputDecoration(
                        hintText: 'Nueva Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          splashRadius: 20,
                          onPressed: () => modalSetState(() {
                            verNueva = !verNueva;
                          }),
                          icon: Icon(
                            verNueva ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        final nueva = (value ?? '').trim();
                        final actual = _passwordActualController.text.trim();

                        if (nueva.isEmpty) {
                          return 'Ingresa una nueva contraseña';
                        }
                        if (nueva.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                        if (actual.isNotEmpty && nueva == actual) {
                          return 'La nueva contraseña no puede ser igual a la actual';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),

                    const SizedBox(height: 16),

                    // CONFIRMAR CONTRASEÑA
                    TextFormField(
                      controller: _confirmarPasswordController,
                      obscureText: !verConfirmar,
                      style: const TextStyle(color: AppTheme.textPrimaryColor),
                      decoration: InputDecoration(
                        hintText: 'Confirmar Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          splashRadius: 20,
                          onPressed: () => modalSetState(() {
                            verConfirmar = !verConfirmar;
                          }),
                          icon: Icon(
                            verConfirmar
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        final confirmar = (value ?? '').trim();
                        final nueva = _passwordNuevaController.text.trim();

                        if (confirmar.isEmpty) {
                          return 'Confirma tu nueva contraseña';
                        }
                        if (nueva.isNotEmpty && confirmar != nueva) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) async {
                        await _submitCambioContrasena();
                      },
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          await _submitCambioContrasena();
                        },
                        child: const Text('Actualizar Contraseña'),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitCambioContrasena() async {
    final form = _passwordFormKey.currentState;
    if (form == null) return;

    final ok = form.validate();
    if (!ok) return;

    await _cambiarContrasena();
  }

  // ================== TERMS ==================

  void _abrirTerminos() {
    final rol =
        context.read<AuthProvider>().usuario?['tipoUsuario']?.toString() ??
        'cliente';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => TermsAndConditionsModal(userRole: rol),
    );
  }

  // ================== UI HELPERS ==================

  void _mostrarCargando(String mensaje) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(mensaje, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
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

  // ================== BUILD ==================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ NUEVO: SECCIÓN DE CUENTA
            _buildSectionTitle('Cuenta'),
            const SizedBox(height: 12),
            _buildSettingTile(
              'Mi perfil',
              'Ver y editar información',
              Icons.person_outline,
              onTap: _navegarAPerfil,
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('Notificaciones'),
            const SizedBox(height: 12),
            _buildToggleTile(
              'Estado de pedidos',
              _notificacionesPedidos,
              (v) => setState(() => _notificacionesPedidos = v),
            ),
            _buildToggleTile(
              'Promociones y ofertas',
              _notificacionesPromo,
              (v) => setState(() => _notificacionesPromo = v),
            ),
            _buildToggleTile(
              'Nuevos productos',
              _notificacionesProductos,
              (v) => setState(() => _notificacionesProductos = v),
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('Recibir notificaciones por'),
            const SizedBox(height: 12),
            _buildToggleTile(
              'Push',
              _notificacionesPush,
              (v) => setState(() => _notificacionesPush = v),
              icon: Icons.notifications,
            ),
            _buildToggleTile(
              'Email',
              _notificacionesEmail,
              (v) => setState(() => _notificacionesEmail = v),
              icon: Icons.mail_outline,
            ),
            _buildToggleTile(
              'SMS',
              _notificacionesSMS,
              (v) => setState(() => _notificacionesSMS = v),
              icon: Icons.message_outlined,
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('Preferencias'),
            const SizedBox(height: 12),
            _buildSettingTile('Idioma', 'Español', Icons.language),
            _buildSettingTile(
              'Ubicación',
              'Activada',
              Icons.location_on_outlined,
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('Seguridad y Privacidad'),
            const SizedBox(height: 12),
            _buildSettingTile(
              'Cambiar contraseña',
              '',
              Icons.lock_outline,
              onTap: _mostrarModalCambiarContrasena,
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('Legal'),
            const SizedBox(height: 12),
            _buildSettingTile(
              'Términos y condiciones',
              '',
              Icons.description_outlined,
              onTap: _abrirTerminos,
            ),
            _buildSettingTile(
              'Versión de la app',
              'v1.0.0',
              Icons.info_outline,
            ),
            const SizedBox(height: 24),
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

  Widget _buildToggleTile(
    String title,
    bool value,
    Function(bool) onChanged, {
    IconData? icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimaryColor,
                fontSize: 14,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) => onChanged(v),
            activeTrackColor: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    String title,
    String subtitle,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondaryColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textSecondaryColor,
              ),
          ],
        ),
      ),
    );
  }
}
