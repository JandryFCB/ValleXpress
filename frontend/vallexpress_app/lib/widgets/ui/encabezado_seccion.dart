import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Título de una sección dentro de una pantalla, con subtítulo y una acción opcional a la derecha.
class EncabezadoSeccion extends StatelessWidget {
  const EncabezadoSeccion(this.titulo, {super.key, this.subtitulo, this.accion});

  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitulo!, style: tema.bodySmall?.copyWith(color: context.colores.textoSuave)),
                ],
              ],
            ),
          ),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}
