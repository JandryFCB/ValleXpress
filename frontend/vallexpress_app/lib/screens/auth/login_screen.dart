import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
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

  @override
  void dispose() {
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
      Navigator.of(context).pushReplacementNamed(AppConstants.homeRoute);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'No se pudo iniciar sesión'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
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
                          child: TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                            ),
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        FilledButton(
                          onPressed: cargando ? null : _entrar,
                          child: cargando
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Text('Iniciar sesión'),
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
