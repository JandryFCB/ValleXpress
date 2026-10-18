import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tema_provider.dart';
import '../../services/api_error.dart';
import '../../services/profile_service.dart';
import '../legal/documento_legal_screen.dart';
import 'eliminar_cuenta_screen.dart';
import '../inicio/tutorial_screen.dart';
import '../../services/version_app.dart';
import '../../widgets/ui/ui.dart';

/// Configuración: apariencia, notificaciones, seguridad y legal.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _clavePedidos = 'pref_notif_pedidos';
  static const _clavePromos = 'pref_notif_promos';

  bool _notifPedidos = true;
  bool _notifPromos = true;

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
  }

  Future<void> _cargarPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifPedidos = prefs.getBool(_clavePedidos) ?? true;
      _notifPromos = prefs.getBool(_clavePromos) ?? true;
    });
  }

  Future<void> _guardarPreferencia(String clave, bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(clave, valor);
  }

  Future<void> _cambiarClave() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FormularioClave(),
    );
    if (ok == true && mounted) mostrarExito(context, 'Contraseña actualizada. Cerramos tus otras sesiones por seguridad.');
  }

  Future<void> _cerrarEnTodos() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión en todos tus dispositivos?'),
        content: const Text('Útil si perdiste tu celular o crees que alguien entró a tu cuenta. También se cerrará la sesión en este dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Cerrar todas')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await context.read<AuthProvider>().cerrarSesionEnTodos();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = context.watch<TemaProvider>();
    final rol = context.read<AuthProvider>().usuario?['tipoUsuario']?.toString() ?? 'cliente';

    return FondoValle(
      titulo: 'Configuración',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ------------------------------ Apariencia ------------------------------
          const EncabezadoSeccion('Apariencia', subtitulo: 'Elige cómo quieres ver la app'),
          TarjetaValle(
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Sistema')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Claro')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Oscuro')),
                ],
                selected: {tema.modo},
                onSelectionChanged: (s) => tema.cambiar(s.first),
              ),
            ),
          ),

          // ------------------------------ Notificaciones ------------------------------
          const SizedBox(height: 16),
          const EncabezadoSeccion('Notificaciones', subtitulo: 'Se guardan en este dispositivo'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.local_shipping_outlined),
                  title: Text(rol == 'cliente' ? 'Estado de mis pedidos' : 'Pedidos'),
                  subtitle: Text(rol == 'cliente' ? 'Cuando tu pedido avance o llegue' : 'Pedidos nuevos y cambios de estado'),
                  value: _notifPedidos,
                  onChanged: (v) {
                    setState(() => _notifPedidos = v);
                    _guardarPreferencia(_clavePedidos, v);
                  },
                ),
                Divider(height: 1, color: context.colores.borde),
                SwitchListTile(
                  secondary: const Icon(Icons.local_offer_outlined),
                  title: const Text('Promociones y novedades'),
                  subtitle: const Text('Ofertas de los negocios de tu zona'),
                  value: _notifPromos,
                  onChanged: (v) {
                    setState(() => _notifPromos = v);
                    _guardarPreferencia(_clavePromos, v);
                  },
                ),
              ],
            ),
          ),

          // ------------------------------ Seguridad ------------------------------
          const SizedBox(height: 16),
          const EncabezadoSeccion('Seguridad'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Cambiar contraseña'), trailing: const Icon(Icons.chevron_right_rounded), onTap: _cambiarClave),
                Divider(height: 1, color: context.colores.borde),
                ListTile(
                  leading: const Icon(Icons.devices_other_rounded),
                  title: const Text('Cerrar sesión en todos mis dispositivos'),
                  subtitle: const Text('Si perdiste tu celular o sospechas de tu cuenta'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _cerrarEnTodos,
                ),
                if (rol != 'administrador') ...[
                  Divider(height: 1, color: context.colores.borde),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_outlined, color: AppTheme.errorColor),
                    title: const Text('Eliminar mi cuenta', style: TextStyle(color: AppTheme.errorColor)),
                    subtitle: const Text('Borra tus datos personales de ValleXpress'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EliminarCuentaScreen())),
                  ),
                ],
              ],
            ),
          ),

          // ------------------------------ Legal ------------------------------
          const SizedBox(height: 16),
          const EncabezadoSeccion('Legal e información'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (rol != 'administrador') ...[
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Términos y condiciones'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => abrirDocumentoLegal(context, 'terminos-$rol'),
                  ),
                  Divider(height: 1, color: context.colores.borde),
                ],
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Ver el tutorial'),
                  subtitle: const Text('Lo que puedes hacer en la app'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => TutorialScreen.abrir(context, rol),
                ),
                Divider(height: 1, color: context.colores.borde),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Política de privacidad'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => abrirDocumentoLegal(context, 'privacidad'),
                ),
                Divider(height: 1, color: context.colores.borde),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Versión de la app'),
                  trailing: FutureBuilder<String>(future: VersionApp.texto(), builder: (_, v) => Text(v.data ?? '')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior para cambiar la contraseña estando con la sesión iniciada
class _FormularioClave extends StatefulWidget {
  const _FormularioClave();

  @override
  State<_FormularioClave> createState() => _FormularioClaveState();
}

class _FormularioClaveState extends State<_FormularioClave> {
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _confirmar = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_actual, _nueva, _confirmar]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _coinciden => _confirmar.text.isNotEmpty && _nueva.text == _confirmar.text;

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (_actual.text.isEmpty) return setState(() => _error = 'Escribe tu contraseña actual');
    if (_nueva.text.length < 6) return setState(() => _error = 'La nueva contraseña debe tener al menos 6 caracteres');
    if (_nueva.text != _confirmar.text) return setState(() => _error = 'Las contraseñas no coinciden');

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ProfileService.cambiarContrasena(passwordActual: _actual.text, passwordNueva: _nueva.text, confirmarPassword: _confirmar.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cambiar contraseña', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            CampoValle(controller: _actual, etiqueta: 'Contraseña actual', icono: Icons.lock_outline, esClave: true, maxLongitud: 72, autofill: const [AutofillHints.password]),
            const SizedBox(height: 14),
            CampoValle(controller: _nueva, etiqueta: 'Contraseña nueva', icono: Icons.lock_reset_outlined, esClave: true, maxLongitud: 72, autofill: const [AutofillHints.newPassword], onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            MedidorClave(clave: _nueva.text),
            const SizedBox(height: 14),
            CampoValle(
              controller: _confirmar,
              etiqueta: 'Confirmar contraseña nueva',
              icono: Icons.lock_reset_outlined,
              esClave: true,
              maxLongitud: 72,
              accion: TextInputAction.done,
              estado: _confirmar.text.isEmpty ? EstadoCampo.neutro : (_coinciden ? EstadoCampo.correcto : EstadoCampo.error),
              ayuda: _error ?? (_confirmar.text.isEmpty ? 'Cerraremos tus sesiones en otros dispositivos' : (_coinciden ? 'Las contraseñas coinciden' : 'Las contraseñas no coinciden')),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _guardando ? null : _guardar(),
            ),
            if (_error != null && _confirmar.text.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 6),
                child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.errorColor)),
              ),
            const SizedBox(height: 20),
            BotonValle(texto: 'Guardar contraseña', icono: Icons.check_rounded, cargando: _guardando, onPressed: _guardar),
          ],
        ),
      ),
    );
  }
}
