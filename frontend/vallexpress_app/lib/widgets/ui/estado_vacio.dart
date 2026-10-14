import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'boton_valle.dart';

/// Pantalla "no hay nada aquí todavía" (o "algo salió mal"): ícono, título, explicación y una acción opcional.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.textoAccion,
    this.onAccion,
    this.color,
  });

  final IconData icono;
  final String titulo;
  final String? mensaje;
  final String? textoAccion;
  final VoidCallback? onAccion;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final tinte = color ?? c.primario;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tinte.withValues(alpha: 0.12)),
              child: Icon(icono, size: 44, color: tinte),
            ),
            const SizedBox(height: 20),
            Text(titulo, style: tema.titleLarge, textAlign: TextAlign.center),
            if (mensaje != null) ...[
              const SizedBox(height: 8),
              Text(mensaje!, style: tema.bodyMedium, textAlign: TextAlign.center),
            ],
            if (textoAccion != null && onAccion != null) ...[
              const SizedBox(height: 24),
              BotonValle(texto: textoAccion!, onPressed: onAccion, anchoCompleto: false),
            ],
          ],
        ),
      ),
    );
  }
}
