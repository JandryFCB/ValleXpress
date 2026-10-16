import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../widgets/ui/ui.dart';
import '../../config/theme.dart';
import '../profile/perfil_screen.dart';
import 'mi_negocio_screen.dart';
import 'pedidos_negocio_screen.dart';

/// Inicio del vendedor: pestañas Pedidos, Mi negocio y Perfil. Un pedido nuevo vibra fuerte y avisa arriba aunque
/// esté en otra pestaña; la pestaña Pedidos muestra cuántos esperan respuesta.
class InicioVendedorScreen extends StatefulWidget {
  const InicioVendedorScreen({super.key});

  @override
  State<InicioVendedorScreen> createState() => _InicioVendedorScreenState();
}

class _InicioVendedorScreenState extends State<InicioVendedorScreen> {
  int _pestana = 0;
  int _porAceptar = 0;
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
      }),
    );
    _subs.add(TiempoReal.instancia.cambios().listen((_) => _contar()));
    _contar();
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

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return AtrasEnPestanas(
      pestana: _pestana,
      irAPrimera: () => setState(() => _pestana = 0),
      child: Scaffold(
        body: PestanasAnimadas(indice: _pestana, children: const [PedidosNegocioScreen(conFlechaAtras: false), MiNegocioScreen(), PerfilScreen()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _pestana,
          backgroundColor: c.tarjeta,
          indicatorColor: c.primario.withValues(alpha: 0.18),
          onDestinationSelected: (i) => setState(() => _pestana = i),
          destinations: [
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
