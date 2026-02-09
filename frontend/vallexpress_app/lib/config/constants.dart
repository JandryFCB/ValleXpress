class AppConstants {
  // API URL - PRODUCCIÓN
  // Cambiar esta URL por tu dominio/IP público cuando subas a producción
  // Ejemplo: https://api.vallexpress.com/api
  static const String baseUrl = 'http://192.168.0.104:3000/api';
  static const String socketUrl = 'http://192.168.0.104:3000';

  // Storage keys
  static const String tokenKey = 'token';
  static const String userKey = 'user';

  // Rutas
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String homeRoute = '/home';
  // Opcional: si luego haces endpoints de imágenes o uploads
  static const String uploadsUrl = '$baseUrl/uploads';

  // Default coordinates (fallback cuando no hay datos del backend)
  // Usar 0,0 para forzar que se carguen datos reales de la BD
  static const double vendorLat = 0.0;
  static const double vendorLng = 0.0;
  static const double clientLat = 0.0;
  static const double clientLng = 0.0;
}
