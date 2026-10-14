import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Imagen descargada del servidor con su "cargando" y un respaldo si no hay imagen o falla la descarga.
class ImagenRed extends StatelessWidget {
  const ImagenRed({super.key, required this.url, this.ancho, this.alto, this.radio = 16, this.icono = Icons.image_outlined, this.fit = BoxFit.cover});

  final String? url;
  final double? ancho;
  final double? alto;
  final double radio;
  final IconData icono;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    Widget respaldo() => Container(
          width: ancho,
          height: alto,
          color: c.tarjetaElevada,
          alignment: Alignment.center,
          child: Icon(icono, color: c.textoSuave, size: (alto ?? 48) * 0.4 > 40 ? 40 : (alto ?? 48) * 0.4),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: url == null || url!.isEmpty
          ? respaldo()
          : Image.network(
              url!,
              width: ancho,
              height: alto,
              fit: fit,
              errorBuilder: (_, __, ___) => respaldo(),
              loadingBuilder: (_, hijo, progreso) => progreso == null ? hijo : respaldo(),
            ),
    );
  }
}
