import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class AddressService {
  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token =
        prefs.getString(AppConstants.tokenKey) ?? prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Token no encontrado');
    }
    return token;
  }

  // Listar todas las direcciones del usuario autenticado
  static Future<List<dynamic>> listar() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('${AppConstants.baseUrl}/direcciones'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      try {
        final d = jsonDecode(res.body);
        throw Exception(d['error'] ?? 'Error al listar direcciones');
      } catch (_) {
        throw Exception('Error al listar direcciones (${res.statusCode})');
      }
    }
    final decoded = jsonDecode(res.body);
    return (decoded['direcciones'] as List?) ?? [];
  }

  // Obtener la dirección predeterminada
  static Future<Map<String, dynamic>?> predeterminada() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('${AppConstants.baseUrl}/direcciones/predeterminada'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    // Si no hay dirección predeterminada, retornar null sin error
    if (res.statusCode == 404) {
      return null;
    }
    if (res.statusCode != 200) {
      try {
        final d = jsonDecode(res.body);
        throw Exception(d['error'] ?? 'Error al obtener predeterminada');
      } catch (_) {
        throw Exception('Error al obtener predeterminada (${res.statusCode})');
      }
    }
    final decoded = jsonDecode(res.body);
    final direccion = decoded['direccion'] as Map<String, dynamic>?;

    // Asegurar que latitud y longitud sean doubles (pueden venir como String del backend)
    if (direccion != null) {
      if (direccion['latitud'] != null) {
        direccion['latitud'] = (direccion['latitud'] is num)
            ? (direccion['latitud'] as num).toDouble()
            : double.tryParse(direccion['latitud'].toString()) ?? 0.0;
      }
      if (direccion['longitud'] != null) {
        direccion['longitud'] = (direccion['longitud'] is num)
            ? (direccion['longitud'] as num).toDouble()
            : double.tryParse(direccion['longitud'].toString()) ?? 0.0;
      }
    }

    return direccion;
  }

  // Crear dirección
  static Future<Map<String, dynamic>> crear({
    String? nombre,
    required String direccion,
    required double latitud,
    required double longitud,
    bool esPredeterminada = false,
  }) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('${AppConstants.baseUrl}/direcciones'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'nombre': nombre,
        'direccion': direccion,
        'latitud': latitud,
        'longitud': longitud,
        'esPredeterminada': esPredeterminada,
      }),
    );
    if (res.statusCode != 201) {
      try {
        final d = jsonDecode(res.body);
        throw Exception(d['error'] ?? 'Error al crear dirección');
      } catch (_) {
        throw Exception('Error al crear dirección (${res.statusCode})');
      }
    }
    final decoded = jsonDecode(res.body);
    return decoded['direccion'] as Map<String, dynamic>;
  }

  // Actualizar dirección
  static Future<Map<String, dynamic>> actualizar(
    String id, {
    String? nombre,
    String? direccion,
    double? latitud,
    double? longitud,
    bool? esPredeterminada,
  }) async {
    final token = await _getToken();
    final res = await http.put(
      Uri.parse('${AppConstants.baseUrl}/direcciones/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (nombre != null) 'nombre': nombre,
        if (direccion != null) 'direccion': direccion,
        if (latitud != null) 'latitud': latitud,
        if (longitud != null) 'longitud': longitud,
        if (esPredeterminada != null) 'esPredeterminada': esPredeterminada,
      }),
    );
    if (res.statusCode != 200) {
      try {
        final d = jsonDecode(res.body);
        throw Exception(d['error'] ?? 'Error al actualizar dirección');
      } catch (_) {
        throw Exception('Error al actualizar dirección (${res.statusCode})');
      }
    }
    final decoded = jsonDecode(res.body);
    return decoded['direccion'] as Map<String, dynamic>;
  }

  // Marcar como predeterminada
  static Future<Map<String, dynamic>> marcarPredeterminada(String id) async {
    final token = await _getToken();
    final res = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/direcciones/$id/predeterminada'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      try {
        final d = jsonDecode(res.body);
        throw Exception(d['error'] ?? 'Error al marcar predeterminada');
      } catch (_) {
        throw Exception('Error al marcar predeterminada (${res.statusCode})');
      }
    }
    final decoded = jsonDecode(res.body);
    return decoded['direccion'] as Map<String, dynamic>;
  }

  // Eliminar
  static Future<void> eliminar(String id) async {
    final token = await _getToken();
    final res = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/direcciones/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      try {
        final d = jsonDecode(res.body);
        throw Exception(d['error'] ?? 'Error al eliminar dirección');
      } catch (_) {
        throw Exception('Error al eliminar dirección (${res.statusCode})');
      }
    }
  }
}
