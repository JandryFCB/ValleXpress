import 'package:flutter/material.dart';
import '../../services/password_reset_service.dart';
import '../../utils/validadores.dart';
import '../../widgets/ui/ui.dart';
import 'verify_code_screen.dart';

/// Recuperar contraseña, paso 1 de 3: pedir el código al correo.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _correo = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _correo.dispose();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    FocusScope.of(context).unfocus();
    final email = _correo.text.trim().toLowerCase();
    if (!Validadores.email(email)) {
      mostrarError(context, 'Escribe un correo válido');
      return;
    }

    setState(() => _cargando = true);
    try {
      await PasswordResetService.forgotPassword(email);
      if (!mounted) return;
      // El servidor responde igual exista o no la cuenta (por seguridad): no se confirma si el correo está registrado
      mostrarMensaje(context, 'Si el correo existe, te enviamos un código.', tipo: TipoMensaje.exito);
      Navigator.push(context, MaterialPageRoute(builder: (_) => VerifyCodeScreen(email: email)));
    } catch (e) {
      if (mounted) mostrarError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PantallaFormulario(
      icono: Icons.lock_reset_rounded,
      titulo: 'Recupera tu contraseña',
      subtitulo: 'Escribe el correo de tu cuenta y te enviaremos un código de 6 dígitos para crear una contraseña nueva.',
      textoBoton: 'Enviar código',
      cargando: _cargando,
      onBoton: _enviarCodigo,
      hijos: [
        CampoValle(
          controller: _correo,
          etiqueta: 'Correo electrónico',
          icono: Icons.alternate_email,
          tipoTeclado: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
          sugerencias: false,
          accion: TextInputAction.done,
          onSubmitted: (_) => _cargando ? null : _enviarCodigo(),
        ),
      ],
    );
  }
}
