import 'package:flutter/material.dart';

/// Etiqueta pequeña de color ("Predeterminada", "Verificado", "Principal"...).
/// El ícono va dentro del mismo texto: si no cabe en una línea (un motivo largo, una pantalla angosta), pasa a la
/// siguiente en vez de salirse del borde, y donde sobra espacio ocupa solo lo que necesita.
class InsigniaValle extends StatelessWidget {
  const InsigniaValle(this.texto, {super.key, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text.rich(
        TextSpan(children: [
          if (icono != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icono, size: 13, color: color)),
            ),
          TextSpan(text: texto),
        ]),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
