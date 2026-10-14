import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/password_reset_service.dart';
import '../../widgets/ui/ui.dart';
import 'new_password_screen.dart';

/// Recuperar contraseña, paso 2 de 3: escribir el código que llegó al correo (se verifica solo al completar los 6 dígitos).
class VerifyCodeScreen extends StatefulWidget {
  final String email;
  const VerifyCodeScreen({super.key, required this.email});

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _codigo = TextEditingController();
  bool _cargando = false;
  bool _reenviando = false;
  int _espera = 60; // el servidor no deja pedir otro código antes de 60 segundos
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _iniciarEspera(60);
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _codigo.dispose();
    super.dispose();
  }

  void _iniciarEspera(int segundos) {
    _reloj?.cancel();
    setState(() => _espera = segundos);
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _espera = _espera > 0 ? _espera - 1 : 0);
      if (_espera == 0) t.cancel();
    });
  }

  Future<void> _verificar() async {
    FocusScope.of(context).unfocus();
    final codigo = _codigo.text.trim();
    if (codigo.length != 6) {
      mostrarError(context, 'El código tiene 6 dígitos');
      return;
    }

    setState(() => _cargando = true);
    try {
      final token = await PasswordResetService.verifyCode(widget.email, codigo);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => NewPasswordScreen(resetToken: token)));
    } catch (e) {
      if (mounted) {
        _codigo.clear();
        mostrarError(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reenviar() async {
    setState(() => _reenviando = true);
    try {
      await PasswordResetService.forgotPassword(widget.email);
      if (!mounted) return;
      mostrarExito(context, 'Te enviamos un código nuevo');
      _iniciarEspera(60);
    } catch (e) {
      final texto = e.toString();
      final espera = RegExp(r'Espera (\d+) segundos').firstMatch(texto);
      if (espera != null) _iniciarEspera(int.parse(espera.group(1)!));
      if (mounted) mostrarError(context, texto.replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;

    return PantallaFormulario(
      icono: Icons.mark_email_read_outlined,
      titulo: 'Revisa tu correo',
      subtitulo: 'Enviamos un código de 6 dígitos a ${widget.email}. Escríbelo aquí.',
      textoBoton: 'Verificar código',
      cargando: _cargando,
      onBoton: _codigo.text.trim().length == 6 ? _verificar : null,
      pie: TextButton(
        onPressed: (_espera > 0 || _reenviando) ? null : _reenviar,
        child: Text(_reenviando ? 'Enviando...' : (_espera > 0 ? 'Reenviar código en $_espera s' : '¿No llegó? Reenviar código')),
      ),
      hijos: [
        TextField(
          controller: _codigo,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: tema.headlineMedium?.copyWith(letterSpacing: 14, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: tema.headlineMedium?.copyWith(letterSpacing: 14, color: c.borde),
          ),
          onChanged: (v) {
            setState(() {});
            if (v.length == 6 && !_cargando) _verificar();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: c.textoSuave),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Si no lo ves, revisa la carpeta de spam. El código vence en 10 minutos.',
                  style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Cambiar correo'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.infoColor, minimumSize: const Size(0, 40)),
          ),
        ),
      ],
    );
  }
}
