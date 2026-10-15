import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import 'animaciones.dart';

enum TipoBoton { principal, secundario, texto, peligro }

/// Botón estándar de la app. Ocupa todo el ancho, muestra un indicador mientras trabaja y se deshabilita solo.
///
///     BotonValle(texto: 'Guardar', icono: Icons.check, cargando: _guardando, onPressed: _guardar)
class BotonValle extends StatelessWidget {
  const BotonValle({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
    this.cargando = false,
    this.tipo = TipoBoton.principal,
    this.anchoCompleto = true,
  });

  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool cargando;
  final TipoBoton tipo;
  final bool anchoCompleto;

  @override
  Widget build(BuildContext context) {
    final accion = cargando || onPressed == null
        ? null
        : () {
            HapticFeedback.lightImpact();
            onPressed!();
          };
    final c = context.colores;

    final contenido = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (hijo, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: hijo)),
      child: cargando
          ? SizedBox(
              key: const ValueKey('cargando'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: tipo == TipoBoton.principal || tipo == TipoBoton.peligro ? Colors.white : c.primario,
              ),
            )
          : Row(
              key: const ValueKey('texto'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icono != null) ...[Icon(icono, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(texto, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    final minimo = anchoCompleto ? const Size.fromHeight(54) : const Size(0, 54);

    Widget boton;
    switch (tipo) {
      case TipoBoton.secundario:
        boton = OutlinedButton(onPressed: accion, style: OutlinedButton.styleFrom(minimumSize: minimo), child: contenido);
      case TipoBoton.texto:
        boton = TextButton(onPressed: accion, style: TextButton.styleFrom(minimumSize: minimo), child: contenido);
      case TipoBoton.peligro:
        boton = FilledButton(
          onPressed: accion,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor, minimumSize: minimo),
          child: contenido,
        );
      case TipoBoton.principal:
        boton = FilledButton(onPressed: accion, style: FilledButton.styleFrom(minimumSize: minimo), child: contenido);
    }
    boton = Pulsable(onTap: accion, child: boton);
    return anchoCompleto ? SizedBox(width: double.infinity, child: boton) : boton;
  }
}
