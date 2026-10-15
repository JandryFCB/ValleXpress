import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import 'animaciones.dart';

/// Tarjeta estándar con los colores del tema (claro u oscuro). Si recibe [onTap] reacciona al toque.
class TarjetaValle extends StatelessWidget {
  const TarjetaValle({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.colorBorde,
    this.radio = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? colorBorde;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radio),
      side: BorderSide(color: colorBorde ?? c.borde),
    );
    final tarjeta = Material(
      color: color ?? c.tarjeta,
      shape: forma,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap!();
              },
              customBorder: forma,
              child: Padding(padding: padding, child: child),
            ),
    );
    // Tocable: se hunde un poco al presionarla
    return onTap == null ? tarjeta : Pulsable(onTap: onTap, child: tarjeta);
  }
}
