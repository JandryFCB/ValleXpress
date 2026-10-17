import 'package:flutter/material.dart';
import '../../services/api_error.dart';
import '../../config/theme.dart';
import '../../services/password_reset_service.dart';
import '../../widgets/ui/ui.dart';

/// Recuperar contraseña, paso 3 de 3: elegir la contraseña nueva. Al terminar, el servidor cierra las sesiones
/// anteriores de la cuenta y se vuelve al inicio de sesión.
class NewPasswordScreen extends StatefulWidget {
  final String resetToken;
  const NewPasswordScreen({super.key, required this.resetToken});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _clave = TextEditingController();
  final _confirmar = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _clave.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  bool get _coinciden => _confirmar.text.isNotEmpty && _clave.text == _confirmar.text;

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (_clave.text.length < 6) {
      mostrarError(context, 'La contraseña debe tener al menos 6 caracteres');
      return;
    }
    if (_clave.text != _confirmar.text) {
      mostrarError(context, 'Las contraseñas no coinciden');
      return;
    }

    setState(() => _cargando = true);
    try {
      await PasswordResetService.resetPassword(widget.resetToken, _clave.text);
      if (!mounted) return;
      mostrarExito(context, 'Contraseña actualizada. Ya puedes iniciar sesión.');
      Navigator.popUntil(context, (ruta) => ruta.isFirst); // vuelve al inicio de sesión
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PantallaFormulario(
      icono: Icons.verified_user_outlined,
      titulo: 'Crea tu nueva contraseña',
      subtitulo: 'Elige una contraseña segura. Cerraremos tus sesiones anteriores por seguridad.',
      textoBoton: 'Guardar contraseña',
      cargando: _cargando,
      onBoton: _guardar,
      hijos: [
        CampoValle(
          controller: _clave,
          etiqueta: 'Contraseña nueva',
          icono: Icons.lock_outline,
          esClave: true,
          maxLongitud: 72,
          autofill: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        MedidorClave(clave: _clave.text),
        const SizedBox(height: 18),
        CampoValle(
          controller: _confirmar,
          etiqueta: 'Confirmar contraseña',
          icono: Icons.lock_reset_outlined,
          esClave: true,
          maxLongitud: 72,
          accion: TextInputAction.done,
          estado: _confirmar.text.isEmpty ? EstadoCampo.neutro : (_coinciden ? EstadoCampo.correcto : EstadoCampo.error),
          ayuda: _confirmar.text.isEmpty ? null : (_coinciden ? 'Las contraseñas coinciden' : 'Las contraseñas no coinciden'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _cargando ? null : _guardar(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(Icons.shield_outlined, size: 16, color: AppTheme.infoColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Este enlace se puede usar una sola vez y vence en 10 minutos.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colores.textoSuave),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
