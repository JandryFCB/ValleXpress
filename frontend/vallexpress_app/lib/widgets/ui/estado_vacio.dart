import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/conectividad.dart';
import '../../config/theme.dart';
import 'boton_valle.dart';

/// Pantalla "no hay nada aquí todavía" (o "algo salió mal"): ícono, título, explicación y una acción opcional.
/// Si la acción es "Reintentar" (un error de carga), se reintenta SOLA: apenas vuelve la red, al regresar a la app
/// y cada 15 s mientras la pantalla está a la vista. El botón sigue ahí por si el usuario no quiere esperar.
class EstadoVacio extends StatefulWidget {
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
  State<EstadoVacio> createState() => _EstadoVacioState();
}

class _EstadoVacioState extends State<EstadoVacio> with WidgetsBindingObserver {
  StreamSubscription? _red;
  Timer? _periodico;

  bool get _reintenta => widget.textoAccion == 'Reintentar' && widget.onAccion != null;

  @override
  void initState() {
    super.initState();
    if (!_reintenta) return;
    WidgetsBinding.instance.addObserver(this);
    _red = Conectividad.volvio.listen((_) => _reintentar());
    _periodico = Timer.periodic(const Duration(seconds: 15), (_) => _reintentar());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _reintentar();
  }

  // Solo si la pantalla está a la vista (no reintenta pestañas ocultas ni pantallas tapadas por otra)
  void _reintentar() {
    if (!mounted || !TickerMode.of(context) || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    widget.onAccion?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _red?.cancel();
    _periodico?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icono = widget.icono;
    final titulo = widget.titulo;
    final mensaje = widget.mensaje;
    final textoAccion = widget.textoAccion;
    final onAccion = widget.onAccion;
    final color = widget.color;
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
              Text(mensaje, style: tema.bodyMedium, textAlign: TextAlign.center),
            ],
            if (textoAccion != null && onAccion != null) ...[
              const SizedBox(height: 24),
              BotonValle(texto: textoAccion, onPressed: onAccion, anchoCompleto: false),
            ],
          ],
        ),
      ),
    );
  }
}
