import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mensaje.dart';

/// Botón/gesto "atrás" en un inicio con pestañas: desde otra pestaña vuelve a la primera; en la primera pide
/// tocar atrás otra vez (en 2 s) para salir, en vez de cerrar la app de golpe.
class AtrasEnPestanas extends StatefulWidget {
  const AtrasEnPestanas({super.key, required this.pestana, required this.irAPrimera, required this.child});

  final int pestana;
  final VoidCallback irAPrimera;
  final Widget child;

  @override
  State<AtrasEnPestanas> createState() => _AtrasEnPestanasState();
}

class _AtrasEnPestanasState extends State<AtrasEnPestanas> {
  DateTime? _ultimoAtras;

  void _alVolver(bool salio, Object? _) {
    if (salio) return;
    if (widget.pestana != 0) {
      widget.irAPrimera();
      return;
    }
    final ahora = DateTime.now();
    if (_ultimoAtras != null && ahora.difference(_ultimoAtras!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _ultimoAtras = ahora;
    HapticFeedback.selectionClick();
    mostrarMensaje(context, 'Toca atrás otra vez para salir');
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, onPopInvokedWithResult: _alVolver, child: widget.child);
}
