import 'package:flutter/foundation.dart';
import '../models/negocio.dart';
import '../models/producto.dart';

/// Un producto en el carrito
class ItemCarrito {
  ItemCarrito({required this.producto, required this.cantidad, this.notas});

  final Producto producto;
  int cantidad;
  String? notas;

  double get subtotal => producto.precio * cantidad;
}

/// Carrito de compras. Como en Rappi o Uber Eats, es de UN solo negocio: si el cliente agrega algo de otro, la
/// pantalla le pregunta si quiere vaciarlo primero. El total es una estimación: el servidor recalcula los precios.
class CarritoProvider with ChangeNotifier {
  Negocio? _negocio;
  final Map<int, ItemCarrito> _items = {};

  static const maxPorProducto = 99;

  Negocio? get negocio => _negocio;
  List<ItemCarrito> get items => _items.values.toList();
  bool get vacio => _items.isEmpty;
  int get cantidadTotal => _items.values.fold(0, (s, i) => s + i.cantidad);
  double get subtotal => _items.values.fold(0.0, (s, i) => s + i.subtotal);
  double get costoEnvio => _negocio?.costoEnvio ?? 0;
  double get total => subtotal + costoEnvio;

  /// Cuánto falta para el pedido mínimo del negocio (0 si ya se alcanzó)
  double get faltaParaMinimo => vacio ? 0 : ((_negocio?.pedidoMinimo ?? 0) - subtotal).clamp(0, double.infinity).toDouble();

  int cantidadDe(int productoId) => _items[productoId]?.cantidad ?? 0;

  /// ¿Agregar un producto de este negocio obligaría a vaciar el carrito?
  bool esDeOtroNegocio(Negocio n) => _negocio != null && !vacio && _negocio!.id != n.id;

  /// Agrega (o suma) unidades. Si el carrito era de otro negocio, se vacía antes: la pantalla ya lo confirmó.
  void agregar(Negocio n, Producto p, {int cantidad = 1, String? notas}) {
    if (esDeOtroNegocio(n)) _items.clear();
    _negocio = n;
    final item = _items[p.id];
    if (item == null) {
      _items[p.id] = ItemCarrito(producto: p, cantidad: cantidad.clamp(1, maxPorProducto), notas: _limpio(notas));
    } else {
      item.cantidad = (item.cantidad + cantidad).clamp(1, maxPorProducto);
      if (_limpio(notas) != null) item.notas = _limpio(notas);
    }
    notifyListeners();
  }

  /// Fija la cantidad de un producto; 0 lo quita del carrito
  void fijarCantidad(int productoId, int cantidad) {
    final item = _items[productoId];
    if (item == null) return;
    if (cantidad <= 0) {
      _items.remove(productoId);
    } else {
      item.cantidad = cantidad.clamp(1, maxPorProducto);
    }
    notifyListeners();
  }

  void fijarNotas(int productoId, String? notas) {
    final item = _items[productoId];
    if (item == null) return;
    item.notas = _limpio(notas);
    notifyListeners();
  }

  /// Actualiza los datos del negocio (costo de envío, abierto...) sin tocar los productos
  void actualizarNegocio(Negocio n) {
    if (_negocio?.id != n.id) return;
    _negocio = n;
    notifyListeners();
  }

  void vaciar() {
    _items.clear();
    _negocio = null;
    notifyListeners();
  }

  /// Lo que se envía al servidor al hacer el pedido
  List<Map<String, dynamic>> paraEnviar() => [
        for (final i in _items.values) {'productoId': i.producto.id, 'cantidad': i.cantidad, if (i.notas != null) 'notas': i.notas},
      ];

  static String? _limpio(String? t) => (t == null || t.trim().isEmpty) ? null : t.trim();
}
