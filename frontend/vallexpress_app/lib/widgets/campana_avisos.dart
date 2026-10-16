import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../screens/pedidos/avisos_screen.dart';
import '../services/pedidos_service.dart';
import '../services/tiempo_real.dart';
import 'ui/ui.dart';

/// Campana de la barra superior con el número de avisos sin leer. Suma en vivo cada aviso nuevo y, al volver de la
/// lista de avisos, se pone al día con el servidor. La usan el vendedor y el repartidor.
class CampanaAvisos extends StatefulWidget {
  const CampanaAvisos({super.key});

  @override
  State<CampanaAvisos> createState() => _CampanaAvisosState();
}

class _CampanaAvisosState extends State<CampanaAvisos> {
  int _noLeidos = 0;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _cargar();
    _subs.add(
      TiempoReal.instancia.avisos.listen((_) {
        if (mounted) setState(() => _noLeidos++);
      }),
    );
    // Al volver la app del segundo plano pudieron llegar avisos que el socket no trajo
    _subs.add(TiempoReal.instancia.cambios().listen((_) => _cargar()));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final n = await PedidosService.avisosNoLeidos();
      if (mounted) setState(() => _noLeidos = n);
    } catch (_) {
      // sin conexión: se queda con lo último que supo
    }
  }

  Future<void> _abrir() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AvisosScreen()));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6), // que el número no quede pegado al borde
      child: IconButton(
        tooltip: _noLeidos > 0 ? 'Avisos ($_noLeidos sin leer)' : 'Avisos',
        onPressed: _abrir,
        icon: Rebote(
          valor: _noLeidos,
          child: Badge(
            isLabelVisible: _noLeidos > 0,
            backgroundColor: AppTheme.errorColor,
            label: Text(_noLeidos > 99 ? '99+' : '$_noLeidos'),
            child: Icon(_noLeidos > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
          ),
        ),
      ),
    );
  }
}
