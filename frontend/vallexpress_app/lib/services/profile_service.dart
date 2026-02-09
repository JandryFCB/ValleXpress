import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class ProfileService {
  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
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
    required String telefono,
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
        'telefono': telefono,
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
  }

  // ===== SUBIR FOTO =====
  // ⚠️ Tu backend actual updateProfile no recibe foto por endpoint separado.
  // Así que aquí te dejo 2 opciones:
  //
  // A) Si solo quieres guardar fotoPerfil como string/base64 en el perfil:
  //    manda fotoPerfil en PUT /auth/profile
  //
  static Future<void> actualizarFotoPerfilBase64(String base64Image) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/auth/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fotoPerfil': base64Image}),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al actualizar foto');
    }
  }

  // Helper: convertir XFile a base64 (si lo necesitas)
  static Future<String> xfileToBase64(XFile image) async {
    final bytes = await image.readAsBytes();
    return base64Encode(bytes);
  }
}
