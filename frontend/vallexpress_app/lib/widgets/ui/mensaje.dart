import 'package:flutter/material.dart';
import '../../config/theme.dart';

enum TipoMensaje { info, exito, error }

/// Aviso flotante estándar (reemplaza a los SnackBar sueltos de cada pantalla). Quita el aviso anterior para que
/// no se acumulen.
void mostrarMensaje(BuildContext context, String texto, {TipoMensaje tipo = TipoMensaje.info}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final (icono, color) = switch (tipo) {
    TipoMensaje.exito => (Icons.check_circle_outline, AppTheme.successColor),
    TipoMensaje.error => (Icons.error_outline, AppTheme.errorColor),
    TipoMensaje.info => (Icons.info_outline, AppTheme.infoColor),
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: tipo == TipoMensaje.error ? 5 : 3),
        content: Row(
          children: [
            Icon(icono, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(texto)),
          ],
        ),
      ),
    );
}

void mostrarError(BuildContext context, String texto) => mostrarMensaje(context, texto, tipo: TipoMensaje.error);
void mostrarExito(BuildContext context, String texto) => mostrarMensaje(context, texto, tipo: TipoMensaje.exito);
