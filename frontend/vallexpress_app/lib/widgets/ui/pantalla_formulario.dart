import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'boton_valle.dart';
import 'fondo_valle.dart';

/// Pantalla de formulario de una sola tarea (recuperar clave, verificar código...): ícono grande, título, explicación,
/// el contenido y un botón principal fijo abajo (por encima del teclado y de los avisos).
class PantallaFormulario extends StatelessWidget {
  const PantallaFormulario({
    super.key,
    required this.titulo,
    required this.icono,
    required this.hijos,
    required this.textoBoton,
    required this.onBoton,
    this.subtitulo,
    this.cargando = false,
    this.pie,
    this.titulosAppBar,
  });

  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final List<Widget> hijos;
  final String textoBoton;
  final VoidCallback? onBoton;
  final bool cargando;

  /// Widget opcional bajo el botón (por ejemplo "¿No llegó? Reenviar")
  final Widget? pie;
  final String? titulosAppBar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;

    return FondoValle(
      titulo: titulosAppBar ?? '',
      barraInferior: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BotonValle(texto: textoBoton, cargando: cargando, onPressed: onBoton),
                  if (pie != null) pie!,
                ],
              ),
            ),
          ),
        ),
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(22)),
                  child: Icon(icono, size: 36, color: c.primario),
                ),
                const SizedBox(height: 24),
                Text(titulo, style: tema.headlineMedium),
                if (subtitulo != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitulo!, style: tema.bodyMedium),
                ],
                const SizedBox(height: 28),
                ...hijos,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
