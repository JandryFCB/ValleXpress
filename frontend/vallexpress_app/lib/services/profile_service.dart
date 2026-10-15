import 'dart:convert';
import 'api_http.dart' as http;
import '../config/constants.dart';
import 'session_store.dart';
import 'session_manager.dart';

class ProfileService {
  static Future<String> _getToken() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Token no encontrado');
    return token;
  }

  // ===== OBTENER PERFIL =====
  static Future<Map<String, dynamic>> obtenerPerfil() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/auth/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Tu backend responde { usuario: {...} }
      if (data is Map && data['usuario'] != null) {
        return Map<String, dynamic>.from(data['usuario']);
      }

      // fallback por si tienes otra forma
      if (data is Map && data['data'] != null) {
        return Map<String, dynamic>.from(data['data']);
      }

      return Map<String, dynamic>.from(data);
    }

    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    throw Exception(body?['error'] ?? 'Error al obtener perfil');
  }

  // ===== ACTUALIZAR PERFIL =====
  static Future<void> actualizarPerfil({
    required String nombre,
    required String apellido,
    String? telefono,
  }) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/auth/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'nombre': nombre,
        'apellido': apellido,
        if (telefono != null) 'telefono': telefono,
      }),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al actualizar perfil');
    }
  }

  // ===== CAMBIAR CONTRASEÑA (LOGUEADO) =====
  static Future<void> cambiarContrasena({
    required String passwordActual,
    required String passwordNueva,
    required String confirmarPassword,
  }) async {
    final token = await _getToken();

    if (passwordNueva != confirmarPassword) {
      throw Exception('Las contraseñas no coinciden');
    }

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/auth/change-password'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'passwordActual': passwordActual,
        'passwordNueva': passwordNueva,
      }),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al cambiar contraseña');
    }

    // El servidor cierra las sesiones de los demás equipos y entrega una sesión nueva para este: hay que guardarla,
    // si no, esta app también quedaría fuera.
    try {
      final datos = jsonDecode(response.body) as Map<String, dynamic>;
      if (datos['token'] != null && datos['refreshToken'] != null) {
        await SessionManager.instance.guardarSesion(
          acceso: datos['token'] as String,
          refresh: datos['refreshToken'] as String,
        );
      }
    } catch (_) {
      // respuesta sin sesión nueva (servidor viejo): no pasa nada
    }
  }

  // ===== FOTO DE PERFIL =====
  /// Sube la foto (base64; el servidor la optimiza a WebP y le quita los datos GPS). Devuelve su URL.
  static Future<String?> subirFoto(String base64Image) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/usuarios/foto-perfil'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'foto': base64Image}),
    );
    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'No se pudo subir la foto');
    }
    return (jsonDecode(response.body)['data']?['fotoPerfil'])?.toString();
  }
}
