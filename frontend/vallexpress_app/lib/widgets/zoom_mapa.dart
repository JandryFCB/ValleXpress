import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../config/theme.dart';

/// Botones + y − para acercar y alejar el mapa. Solo en la web: con el mouse no hay pellizco (el doble clic solo
/// acerca). En el celular no se muestran.
class ZoomMapa extends StatelessWidget {
  const ZoomMapa({super.key, required this.mapa});

  final MapController mapa;

  void _zoom(double cambio) {
    final camara = mapa.camera;
    mapa.move(camara.center, (camara.zoom + cambio).clamp(camara.minZoom ?? 3, camara.maxZoom ?? 19));
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final c = context.colores;
    Widget boton(IconData icono, String texto, double cambio) => IconButton(
          tooltip: texto,
          onPressed: () => _zoom(cambio),
          icon: Icon(icono, color: c.texto),
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        );
    return Material(
      color: c.tarjeta,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.borde)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton(Icons.add_rounded, 'Acercar', 1),
          Container(width: 28, height: 1, color: c.borde),
          boton(Icons.remove_rounded, 'Alejar', -1),
        ],
      ),
    );
  }
}
