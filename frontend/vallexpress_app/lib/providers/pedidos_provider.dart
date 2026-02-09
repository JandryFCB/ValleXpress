import 'package:flutter/material.dart';
import '../services/pedido_service.dart';

class PedidosProvider with ChangeNotifier {
  List<dynamic> _pedidos = [];
  bool _loading = false;

  List<dynamic> get pedidos => _pedidos;
  bool get loading => _loading;

  /// Pedido activo = primer pedido en_camino
  Map<String, dynamic>? get pedidoActivo {
    try {
      return _pedidos.firstWhere((p) => p['estado'] == 'en_camino');
    } catch (_) {
      return null;
    }
  }

  Future<void> cargarMisPedidos() async {
    _loading = true;
    notifyListeners();

    try {
      _pedidos = await PedidoService.misPedidos();
    } catch (e) {
      _pedidos = [];
    }

    _loading = false;
    notifyListeners();
  }

  void clear() {
    _pedidos = [];
    notifyListeners();
  }
}
