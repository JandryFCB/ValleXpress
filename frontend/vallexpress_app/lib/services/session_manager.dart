import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'session_store.dart';

/// Renueva la sesión con el refresh token. Reglas importantes:
///  * Una sola renovación a la vez ("single-flight"): el servidor ROTA el refresh token en cada canje, así que dos
///    renovaciones en paralelo con el mismo token se verían como un robo y cerrarían la sesión.
///  * Sin internet NO se cierra la sesión: se devuelve false y se reintenta en la próxima petición.
///  * Solo se cierra la sesión cuando el servidor dice que ya no sirve (vencida, cerrada, reutilizada, desactivada).
class SessionManager {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  /// Cliente HTTP (se cambia en las pruebas)
  http.Client cliente = http.Client();

  Future<bool>? _enCurso;

  final StreamController<String> _renovado = StreamController<String>.broadcast();
  final StreamController<String> _terminada = StreamController<String>.broadcast();

  /// Emite el token de acceso nuevo cada vez que se renueva
  Stream<String> get renovado => _renovado.stream;

  /// Emite el código del servidor cuando la sesión ya no es válida (la app debe volver al login)
  Stream<String> get sesionTerminada => _terminada.stream;

  static const Set<String> _codigosFin = {
    'REFRESHINVALIDO',
    'SESIONCERRADA',
    'REFRESHEXPIRADO',
    'REFRESHREUTILIZADO',
    'CUENTADESACTIVADA',
  };

  /// Mensaje para mostrar al usuario según por qué terminó la sesión
  static String mensajeDe(String codigo) {
    switch (codigo) {
      case 'REFRESHEXPIRADO':
        return 'Tu sesión expiró por inactividad. Inicia sesión de nuevo.';
      case 'REFRESHREUTILIZADO':
        return 'Por seguridad cerramos tu sesión. Inicia sesión de nuevo.';
      case 'CUENTADESACTIVADA':
        return 'Tu cuenta está desactivada.';
      default:
        return 'Tu sesión se cerró. Inicia sesión de nuevo.';
    }
  }

  /// Guarda una sesión recién entregada por el servidor (login, registro o cambio de clave) y avisa a los
  /// que escuchan para que usen el token nuevo.
  Future<void> guardarSesion({required String acceso, required String refresh}) async {
    await SessionStore.guardar(acceso: acceso, refresh: refresh);
    _renovado.add(acceso);
  }

  /// Canjea el refresh token por un par nuevo. Devuelve true si la sesión quedó renovada.
  Future<bool> refrescar() => _enCurso ??= _renovar().whenComplete(() => _enCurso = null);

  Future<bool> _renovar() async {
    final refresh = await SessionStore.refreshToken();
    if (refresh == null) return false;

    http.Response res;
    try {
      res = await cliente
          .post(
            Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return false; // sin red o servidor caído: la sesión se conserva
    }

    if (res.statusCode == 200) {
      final datos = jsonDecode(res.body) as Map<String, dynamic>;
      await guardarSesion(acceso: datos['token'] as String, refresh: datos['refreshToken'] as String);
      return true;
    }

    final codigo = _codigoDe(res);
    if (_codigosFin.contains(codigo)) {
      await SessionStore.limpiar();
      _terminada.add(codigo);
    }
    return false;
  }

  static String _codigoDe(http.Response res) {
    try {
      final cuerpo = jsonDecode(res.body);
      return cuerpo is Map ? (cuerpo['code'] ?? '').toString() : '';
    } catch (_) {
      return '';
    }
  }
}
