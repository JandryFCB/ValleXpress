import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show ServicesBinding;

/// Estado de la red del celular (WiFi, datos móviles o nada).
///   * [hayRed]: si el celular está desconectado, las peticiones fallan al instante en vez de esperar el límite
///     de tiempo (antes la app se quedaba ~20 s "cargando" sin internet).
///   * [volvio]: avisa cuando la red regresa, para que las pantallas con "Reintentar" se recarguen solas.
/// Tener WiFi no garantiza internet (un router sin servicio): en ese caso manda el límite de tiempo normal.
class Conectividad {
  Conectividad._();

  static final _conectividad = Connectivity();
  static final _volvio = StreamController<void>.broadcast();
  static StreamSubscription? _sub;
  static bool _conRed = true;

  static Stream<void> get volvio {
    _escuchar();
    return _volvio.stream;
  }

  static bool _tieneRed(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  // Fuera de la app (pruebas de lógica pura) no hay plataforma con quién hablar
  static bool get _hayPlataforma {
    try {
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _escuchar() {
    if (_sub != null || !_hayPlataforma) return;
    try {
      _sub = _conectividad.onConnectivityChanged.listen((r) {
        final ahora = _tieneRed(r);
        if (ahora && !_conRed) _volvio.add(null);
        _conRed = ahora;
      }, onError: (_) {});
    } catch (_) {
      // sin plataforma (pruebas) o sin permiso: no se detectan cambios, las peticiones se intentan igual
    }
  }

  static Future<bool> hayRed() async {
    if (!_hayPlataforma) return true;
    try {
      _escuchar();
      _conRed = _tieneRed(await _conectividad.checkConnectivity());
    } catch (_) {
      _conRed = true; // si el sistema no responde, se intenta igual
    }
    return _conRed;
  }
}
