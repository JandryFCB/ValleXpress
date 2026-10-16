import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/ui/ui.dart';
import 'forgot_password_screen.dart';

/// Pantalla de inicio de sesión. Se adapta al modo claro/oscuro (colores desde context.colores).
/// La sesión queda guardada en el equipo: después de entrar una vez, la app abre directo sin pedir la clave.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _claveController = TextEditingController();
  final _claveFocus = FocusNode();
  bool _ocultarClave = true;

  /// Último aviso del servidor (bloqueo, cuenta desactivada, intentos que quedan) y hasta cuándo dura el bloqueo
  ErrorLogin? _aviso;
  DateTime? _desbloqueo;
  Timer? _reloj;

  Duration get _faltan => _desbloqueo == null ? Duration.zero : _desbloqueo!.difference(DateTime.now());
  bool get _bloqueada => _faltan > Duration.zero;

  void _iniciarCuentaRegresiva(int segundos) {
    _desbloqueo = DateTime.now().add(Duration(seconds: segundos));
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_bloqueada) {
        _reloj?.cancel();
        setState(() => (_aviso = null, _desbloqueo = null));
        mostrarExito(context, 'Ya puedes intentar de nuevo');
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _usuarioController.dispose();
    _claveController.dispose();
    _claveFocus.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_usuarioController.text.trim(), _claveController.text);
    if (!mounted) return;

    if (ok) {
      _reloj?.cancel();
      Navigator.of(context).pushReplacementNamed(AppConstants.homeRoute);
      return;
    }
    final e = auth.errorLogin;
    // Bloqueos y avisos de intentos: tarjeta fija con la explicación. Lo demás (clave mala, sin internet): mensaje breve
    if (e != null && (e.bloqueoTemporal || e.desactivada || e.intentosRestantes != null)) {
      HapticFeedback.heavyImpact();
      setState(() => _aviso = e);
      if (e.bloqueoTemporal) _iniciarCuentaRegresiva(e.segundos ?? 900);
    } else {
      setState(() => _aviso = null);
      mostrarError(context, auth.error ?? 'No se pudo iniciar sesión');
    }
  }

  Future<void> _escribirASoporte(String correo) async {
    final abierto = await launchUrl(Uri(scheme: 'mailto', path: correo, queryParameters: {'subject': 'Ayuda con mi cuenta de ValleXpress'}));
    if (!abierto && mounted) {
      await Clipboard.setData(ClipboardData(text: correo));
      if (mounted) mostrarMensaje(context, 'Copiamos el correo de soporte: $correo');
    }
  }

  // Al cambiar la contraseña la cuenta se desbloquea en el servidor: al volver se quita el aviso y la cuenta
  // regresiva (si sigue bloqueada, el próximo intento lo vuelve a mostrar) y se borra la contraseña vieja
  Future<void> _recuperar() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
    if (!mounted) return;
    _reloj?.cancel();
    _claveController.clear();
    setState(() => (_aviso = null, _desbloqueo = null));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final texto = Theme.of(context).textTheme;
    final cargando = context.select<AuthProvider, bool>((a) => a.isLoading);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.degradadoFondo),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: c.primario.withValues(alpha: 0.28),
                                  blurRadius: 32,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset('assets/images/logo.png', width: 112, height: 112),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        Text('Bienvenido de vuelta', style: texto.headlineMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(
                          'Inicia sesión para pedir lo mejor del valle',
                          style: texto.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Usuario o correo
                        TextFormField(
                          controller: _usuarioController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Correo o usuario',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe tu correo o tu usuario' : null,
                          onFieldSubmitted: (_) => _claveFocus.requestFocus(),
                        ),
                        const SizedBox(height: 16),

                        // Contraseña
                        TextFormField(
                          controller: _claveController,
                          focusNode: _claveFocus,
                          obscureText: _ocultarClave,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _ocultarClave ? 'Mostrar contraseña' : 'Ocultar contraseña',
                              icon: Icon(_ocultarClave ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _ocultarClave = !_ocultarClave),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                          onFieldSubmitted: (_) => cargando ? null : _entrar(),
                        ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: _recuperar, child: const Text('¿Olvidaste tu contraseña?')),
                        ),
                        const SizedBox(height: 8),

                        // Aviso del servidor: bloqueo con cuenta regresiva, cuenta desactivada o intentos que quedan
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (hijo, a) => SizeTransition(sizeFactor: a, child: FadeTransition(opacity: a, child: hijo)),
                          child: _aviso == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  key: ValueKey(_aviso!.codigo),
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _AvisoLogin(
                                    aviso: _aviso!,
                                    faltan: _faltan,
                                    onRecuperar: _recuperar,
                                    onSoporte: _aviso!.soporte == null ? null : () => _escribirASoporte(_aviso!.soporte!),
                                  ),
                                ),
                        ),

                        FilledButton(
                          onPressed: cargando || _bloqueada ? null : _entrar,
                          child: cargando
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : Text(_bloqueada ? 'Espera ${_mmss(_faltan)}' : 'Iniciar sesión'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tu sesión se mantiene iniciada en este equipo. Puedes cerrarla cuando quieras desde tu perfil.',
                          style: texto.bodySmall?.copyWith(color: c.textoSuave),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(child: Divider(color: c.borde)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('¿Eres nuevo?', style: texto.bodySmall?.copyWith(color: c.textoSuave)),
                            ),
                            Expanded(child: Divider(color: c.borde)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pushNamed(AppConstants.registerRoute),
                          child: const Text('Crear una cuenta'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Tarjeta que explica por qué no puede entrar y qué hacer
class _AvisoLogin extends StatelessWidget {
  const _AvisoLogin({required this.aviso, required this.faltan, required this.onRecuperar, this.onSoporte});

  final ErrorLogin aviso;
  final Duration faltan;
  final VoidCallback onRecuperar;
  final VoidCallback? onSoporte;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final (color, icono, titulo) = aviso.bloqueoTemporal
        ? (AppTheme.errorColor, Icons.lock_clock_rounded, 'Cuenta bloqueada por seguridad')
        : aviso.desactivada
            ? (AppTheme.errorColor, aviso.estatus == 'inactivo' ? Icons.person_off_rounded : Icons.block_rounded, aviso.estatus == 'inactivo' ? 'Tu cuenta está dada de baja' : 'Tu cuenta está bloqueada')
            : (AppTheme.warningColor, Icons.warning_amber_rounded, aviso.intentosRestantes == 1 ? 'Te queda 1 intento' : 'Te quedan ${aviso.intentosRestantes} intentos');
    final total = (aviso.segundos ?? 900).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.texto))),
            ],
          ),
          if (aviso.bloqueoTemporal) ...[
            const SizedBox(height: 14),
            // Cuenta regresiva grande con una barra que se vacía
            Center(child: Text(_mmss(faltan), style: tema.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()]))),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: (faltan.inSeconds / total).clamp(0, 1), minHeight: 6, color: color, backgroundColor: color.withValues(alpha: 0.15)),
            ),
            const SizedBox(height: 10),
            Text('Escribieron mal la contraseña varias veces. Espera a que termine el tiempo o recupera tu contraseña: al cambiarla, tu cuenta se desbloquea al instante.',
                style: tema.bodySmall?.copyWith(color: c.textoSuave)),
          ] else ...[
            const SizedBox(height: 8),
            Text(aviso.mensaje, style: tema.bodyMedium?.copyWith(color: c.texto)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!aviso.desactivada)
                FilledButton.tonalIcon(onPressed: onRecuperar, icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Recuperar contraseña')),
              if (onSoporte != null && !(aviso.intentosRestantes != null))
                OutlinedButton.icon(onPressed: onSoporte, icon: const Icon(Icons.support_agent_rounded, size: 18), label: const Text('Contactar a soporte')),
            ],
          ),
          if (aviso.desactivada && aviso.soporte != null) ...[
            const SizedBox(height: 6),
            SelectableText('Soporte: ${aviso.soporte}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
          ],
        ],
      ),
    );
  }
}
