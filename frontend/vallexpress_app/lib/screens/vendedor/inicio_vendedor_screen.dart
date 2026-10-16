import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/negocio.dart';
import '../../services/catalogo_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../widgets/panel_aprobacion.dart';
import '../../widgets/ui/ui.dart';
import '../../config/theme.dart';
import '../profile/perfil_screen.dart';
import 'mi_negocio_screen.dart';
import 'pedidos_negocio_screen.dart';

/// Inicio del vendedor: pestañas Pedidos, Mi negocio y Perfil. Un pedido nuevo vibra fuerte y avisa arriba aunque
/// esté en otra pestaña; la pestaña Pedidos muestra cuántos esperan respuesta. Mientras el negocio no esté
/// aprobado, la primera pestaña es "Solicitud" (en revisión, rechazado o suspendido, con el motivo).
class InicioVendedorScreen extends StatefulWidget {
  const InicioVendedorScreen({super.key});

  @override
  State<InicioVendedorScreen> createState() => _InicioVendedorScreenState();
}

class _InicioVendedorScreenState extends State<InicioVendedorScreen> {
  int _pestana = 0;
  int _porAceptar = 0;
  Negocio? _negocio;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    TiempoReal.instancia.iniciar();
    _subs.add(
      TiempoReal.instancia.avisos.listen((a) {
        if (!mounted) return;
        if (a.tipo == 'pedido_nuevo') {
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        }
        mostrarMensaje(context, a.tipo == 'pedido_nuevo' ? '🛒 ${a.titulo} ${a.mensaje}' : a.titulo);
        // La decisión del administrador sobre el negocio: se recarga al instante
        if (a.tipo.startsWith('negocio_')) {
          _cargarNegocio().then((_) {
            if (mounted && a.tipo == 'negocio_aprobado') Confeti.lanzar(context);
          });
        }
      }),
    );
    _subs.add(
      TiempoReal.instancia.cambios().listen((_) {
        _contar();
        if (_enRevision) _cargarNegocio(); // al volver a la app pudo haber llegado la decisión
      }),
    );
    _contar();
    _cargarNegocio();
  }

  bool get _enRevision => _negocio?.aprobacion != null && _negocio!.aprobacion != 'aprobado';

  Future<void> _cargarNegocio() async {
    try {
      final n = await CatalogoService.miNegocio();
      if (mounted) setState(() => _negocio = n);
    } catch (_) {
      // sin conexión: se queda con lo último que supo
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _contar() async {
    try {
      final r = await PedidosService.pedidosDelNegocio(estado: 'activos');
      final n = r.pedidos.where((p) => p.puedeCancelar).length; // pendientes de aceptar
      if (mounted) setState(() => _porAceptar = n);
    } catch (_) {
      // sin negocio todavía o sin conexión
    }
  }

  // Mientras no esté aprobado: el estado de la solicitud. "Armar mi menú" y "Corregir" llevan a Mi negocio.
  Widget _solicitud() {
    final n = _negocio!;
    return FondoValle(
      appBar: AppBar(title: const Text('Tu solicitud'), automaticallyImplyLeading: false),
      child: PanelAprobacion(
        tipo: TipoSolicitud.negocio,
        aprobacion: n.aprobacion!,
        motivo: n.motivoAprobacion,
        soporte: n.soporte,
        textoMientras: 'Armar mi negocio y mi menú',
        onMientras: () => setState(() => _pestana = 1),
        textoCorregir: 'Corregir mi negocio',
        onCorregir: () => setState(() => _pestana = 1),
        onPedirRevision: () async {
          final actualizado = await CatalogoService.pedirRevisionNegocio();
          if (mounted) setState(() => _negocio = actualizado);
        },
        onActualizar: _cargarNegocio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return AtrasEnPestanas(
      pestana: _pestana,
      irAPrimera: () => setState(() => _pestana = 0),
      child: Scaffold(
        body: PestanasAnimadas(
          indice: _pestana,
          children: [
            _enRevision ? _solicitud() : const PedidosNegocioScreen(conFlechaAtras: false),
            const MiNegocioScreen(),
            const PerfilScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _pestana,
          backgroundColor: c.tarjeta,
          indicatorColor: c.primario.withValues(alpha: 0.18),
          onDestinationSelected: (i) {
            setState(() => _pestana = i);
            if (i == 0) _cargarNegocio(); // pudo crear o corregir su negocio en la otra pestaña
          },
          destinations: [
            if (_enRevision)
              const NavigationDestination(icon: Icon(Icons.hourglass_empty_rounded), selectedIcon: Icon(Icons.hourglass_top_rounded), label: 'Solicitud')
            else
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _porAceptar > 0,
                  backgroundColor: AppTheme.warningColor,
                  label: Text('$_porAceptar'),
                  child: const Icon(Icons.receipt_long_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: _porAceptar > 0,
                  backgroundColor: AppTheme.warningColor,
                  label: Text('$_porAceptar'),
                  child: const Icon(Icons.receipt_long_rounded),
                ),
                label: 'Pedidos',
              ),
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'Mi negocio'),
            const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}
