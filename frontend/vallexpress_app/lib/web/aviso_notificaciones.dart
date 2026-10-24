import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'escritorio.dart';
import '../services/fcm_mobile.dart' if (dart.library.html) '../services/fcm_web.dart';

/// Franja "Activa las notificaciones" (solo en la web): el navegador solo deja pedir el permiso al tocar un botón.
/// Desaparece al activarlas, al tocar "Ahora no" o si el navegador no las admite (iPhone sin la web en el inicio).
class AvisoNotificaciones extends StatefulWidget {
  const AvisoNotificaciones({super.key});

  @override
  State<AvisoNotificaciones> createState() => _AvisoNotificacionesState();
}

class _AvisoNotificacionesState extends State<AvisoNotificaciones> {
  bool _ver = false;
  bool _activando = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    // Firebase se inicia en segundo plano al abrir la web: se revisa un momento después
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _ver = FcmService.permisoPendiente);
    });
  }

  Future<void> _activar() async {
    setState(() => _activando = true);
    final ok = await FcmService.activar();
    if (!mounted) return;
    setState(() {
      _activando = false;
      _ver = false;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Listo: te avisaremos de tus pedidos aunque tengas la página cerrada'
          : 'No se activaron. Puedes permitirlas desde el candado junto a la dirección de la página'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: !_ver
          ? const SizedBox(width: double.infinity)
          : Material(
              color: AppTheme.accentColor.withValues(alpha: 0.14),
              child: SafeArea(
                bottom: false,
                child: LayoutBuilder(builder: (_, medidas) {
                  final texto = Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Activa las notificaciones', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      TextSpan(text: '  para enterarte de tus pedidos aunque cierres la página', style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
                    ]),
                  );
                  final botones = [
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: () {
                        FcmService.descartar();
                        setState(() => _ver = false);
                      },
                      child: const Text('Ahora no'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), // el tema los pone a todo el ancho
                      onPressed: _activando ? null : _activar,
                      child: _activando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Activar'),
                    ),
                  ];
                  final icono = Icon(Icons.notifications_active_rounded, color: c.texto);
                  // Celular: los botones debajo del texto
                  if (medidas.maxWidth < 600) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icono, const SizedBox(width: 12), Expanded(child: texto)]),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: botones),
                      ]),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: margenWeb - 8, vertical: 8), // alineada con la barra
                    child: Row(children: [icono, const SizedBox(width: 12), Expanded(child: texto), const SizedBox(width: 8), ...botones]),
                  );
                }),
              ),
            ),
    );
  }
}
