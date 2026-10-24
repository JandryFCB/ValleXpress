import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de apariencia del usuario: seguir al sistema, siempre claro o siempre oscuro.
/// Se guarda en el teléfono y se aplica al abrir la app.
class TemaProvider with ChangeNotifier {
  static const String _clave = 'tema';

  /// Mientras las pantallas se migran al tema claro/oscuro, la app arranca en oscuro (las que aún usan los
  /// colores fijos se ven bien así). Cuando todas estén migradas, esto pasa a ThemeMode.system.
  /// En la web arranca en claro (se ve como una página normal; el usuario puede cambiarlo en Configuración).
  static const ThemeMode porDefecto = kIsWeb ? ThemeMode.light : ThemeMode.dark;

  ThemeMode _modo = porDefecto;
  ThemeMode get modo => _modo;

  TemaProvider() {
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getString(_clave);
      final modo = ThemeMode.values.where((m) => m.name == guardado);
      if (modo.isNotEmpty && modo.first != _modo) {
        _modo = modo.first;
        notifyListeners();
      }
    } catch (_) {
      // sin preferencias guardadas: se queda con el valor por defecto
    }
  }

  Future<void> cambiar(ThemeMode nuevo) async {
    if (nuevo == _modo) return;
    _modo = nuevo;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, nuevo.name);
    } catch (_) {
      // si no se pudo guardar, el cambio vale solo para esta sesión
    }
  }
}
