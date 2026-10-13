/// Servidores disponibles. Se elige al compilar, sin tocar el código:
///
///   flutter run                                   -> local (localhost, útil en web/escritorio)
///   flutter run --dart-define=ENTORNO=lan --dart-define=IP_LAN=192.168.1.50
///                                                 -> celular real o emulador en la misma red
///   flutter run --dart-define=ENTORNO=emulador    -> emulador Android (10.0.2.2 = tu PC)
///   flutter build apk --dart-define=ENTORNO=prod --dart-define=API_PROD=https://api.tudominio.com
///
/// Para ver tu IP en la red: `ipconfig` (IPv4 de tu adaptador Wi-Fi).
enum Entorno { local, emulador, lan, prod }

class AppConstants {
  static const String _entornoTexto = String.fromEnvironment(
    'ENTORNO',
    defaultValue: 'local',
  );
  static const String _ipLan = String.fromEnvironment(
    'IP_LAN',
    defaultValue: '192.168.1.50',
  );
  static const String _apiProd = String.fromEnvironment(
    'API_PROD',
    defaultValue: 'https://api.vallexpress.com',
  );
  static const String _puerto = String.fromEnvironment(
    'PUERTO',
    defaultValue: '3000',
  );

  static Entorno get entorno => Entorno.values.firstWhere(
    (e) => e.name == _entornoTexto,
    orElse: () => Entorno.local,
  );

  /// Dirección base del servidor (sin /api).
  static String get serverUrl {
    switch (entorno) {
      case Entorno.emulador:
        return 'http://10.0.2.2:$_puerto';
      case Entorno.lan:
        return 'http://$_ipLan:$_puerto';
      case Entorno.prod:
        return _apiProd;
      case Entorno.local:
        return 'http://localhost:$_puerto';
    }
  }

  static String get baseUrl => '$serverUrl/api';
  static String get socketUrl => serverUrl;
  static String get uploadsUrl => '$serverUrl/uploads';

  // Storage keys
  static const String tokenKey = 'token';
  static const String userKey = 'user';

  // Rutas
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String homeRoute = '/home';

  // Coordenadas por defecto (0,0 fuerza a cargar datos reales de la BD)
  static const double vendorLat = 0.0;
  static const double vendorLng = 0.0;
  static const double clientLat = 0.0;
  static const double clientLng = 0.0;
}
