import 'dart:convert';
import '../config/constants.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Direcciones de entrega del usuario (GET/POST/PUT/PATCH/DELETE /api/direcciones). Los métodos devuelven mapas
/// (como antes) para no romper las pantallas que ya los usan; las pantallas nuevas los convierten con
/// `Direccion.desdeJson`. Los errores del servidor llegan con su mensaje real (por ejemplo "Puedes guardar hasta 20
/// direcciones").
class AddressService {
  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Uri _url([String ruta = '']) => Uri.parse('${AppConstants.baseUrl}/direcciones$ruta');

  static Map<String, dynamic> _direccion(http.Response res) {
    final d = (jsonDecode(res.body) as Map<String, dynamic>)['direccion'] as Map<String, dynamic>;
    return d;
  }

  /// Todas las direcciones del usuario (la predeterminada primero)
  static Future<List<dynamic>> listar() async {
    final res = await http.get(_url(), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudieron cargar tus direcciones'));
    return (jsonDecode(res.body) as Map<String, dynamic>)['direcciones'] as List<dynamic>;
  }

  /// La dirección predeterminada, o null si el usuario aún no tiene una (el servidor responde 404 sin error)
  static Future<Map<String, dynamic>?> predeterminada() async {
    final res = await http.get(_url('/predeterminada'), headers: await _cabeceras());
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo cargar la dirección predeterminada'));
    return _direccion(res);
  }

  static Future<Map<String, dynamic>> crear({
    String? nombre,
    required String direccion,
    required double latitud,
    required double longitud,
    bool esPredeterminada = false,
    String? tipo,
    String? referencia,
    String? instrucciones,
  }) async {
    final res = await http.post(
      _url(),
      headers: await _cabeceras(),
      body: jsonEncode({
        'nombre': nombre,
        'direccion': direccion,
        'latitud': latitud,
        'longitud': longitud,
        'esPredeterminada': esPredeterminada,
        if (tipo != null) 'tipo': tipo,
        if (referencia != null) 'referencia': referencia,
        if (instrucciones != null) 'instrucciones': instrucciones,
      }),
    );
    if (res.statusCode != 201) throw Exception(mensajeDeError(res, 'No se pudo guardar la dirección'));
    return _direccion(res);
  }

  static Future<Map<String, dynamic>> actualizar(
    String id, {
    String? nombre,
    String? direccion,
    double? latitud,
    double? longitud,
    bool? esPredeterminada,
    String? tipo,
    String? referencia,
    String? instrucciones,
  }) async {
    final res = await http.put(
      _url('/$id'),
      headers: await _cabeceras(),
      body: jsonEncode({
        if (nombre != null) 'nombre': nombre,
        if (direccion != null) 'direccion': direccion,
        if (latitud != null) 'latitud': latitud,
        if (longitud != null) 'longitud': longitud,
        if (esPredeterminada != null) 'esPredeterminada': esPredeterminada,
        if (tipo != null) 'tipo': tipo,
        if (referencia != null) 'referencia': referencia,
        if (instrucciones != null) 'instrucciones': instrucciones,
      }),
    );
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo actualizar la dirección'));
    return _direccion(res);
  }

  static Future<Map<String, dynamic>> marcarPredeterminada(String id) async {
    final res = await http.patch(_url('/$id/predeterminada'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo marcar como predeterminada'));
    return _direccion(res);
  }

  static Future<void> eliminar(String id) async {
    final res = await http.delete(_url('/$id'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo eliminar la dirección'));
  }
}
