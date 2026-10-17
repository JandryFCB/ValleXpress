import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../screens/profile/permisos_screen.dart';
import '../services/permisos_celular.dart';
import 'ui/ui.dart';

/// Aviso "Tu celular no está listo" con acceso a "Prepara tu celular". Solo aparece si a este rol le falta algún
/// permiso (y se vuelve a revisar al regresar a la app, por si lo activó desde los ajustes). Si todo está bien no
/// ocupa espacio.
class AvisoPermisos extends StatefulWidget {
  const AvisoPermisos({super.key, required this.rol, this.margen = const EdgeInsets.only(bottom: 12)});

  final String rol;
  final EdgeInsets margen;

  @override
  State<AvisoPermisos> createState() => _AvisoPermisosState();
}

class _AvisoPermisosState extends State<AvisoPermisos> with WidgetsBindingObserver {
  bool _falta = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _revisar();
  }

  Future<void> _revisar() async {
    final falta = await PermisosCelular.faltaAlgo(widget.rol);
    if (mounted && falta != _falta) setState(() => _falta = falta);
  }

  Future<void> _abrir() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PermisosScreen(rol: widget.rol)));
    _revisar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: !_falta
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: widget.margen,
              child: TarjetaValle(
                onTap: _abrir,
                color: AppTheme.warningColor.withValues(alpha: 0.12),
                colorBorde: AppTheme.warningColor.withValues(alpha: 0.6),
                child: Row(
                  children: [
                    const Icon(Icons.phonelink_setup_rounded, color: AppTheme.warningColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tu celular no está listo', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            widget.rol == 'repartidor' ? 'Faltan permisos para recibir pedidos y compartir tu ruta' : 'Activa las notificaciones para no perderte ningún pedido',
                            style: tema.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
    );
  }
}
