import 'package:flutter/material.dart';
import '../../config/theme.dart';

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
    final accion = cargando ? null : onPressed;
    final c = context.colores;

    final contenido = cargando
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: tipo == TipoBoton.principal || tipo == TipoBoton.peligro ? Colors.white : c.primario,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icono != null) ...[Icon(icono, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(texto, overflow: TextOverflow.ellipsis)),
            ],
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
    return anchoCompleto ? SizedBox(width: double.infinity, child: boton) : boton;
  }
}
