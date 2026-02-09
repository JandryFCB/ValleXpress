import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class ProductService {
  // ✅ Listar SOLO mis productos (vendedor autenticado)
  static Future<List<dynamic>> listarMisProductos() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/productos/mis-productos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
      '📡 [ProductService] listarMisProductos status: ${response.statusCode}',
    );
    debugPrint('📡 [ProductService] listarMisProductos body: ${response.body}');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['productos'] is List) {
        return decoded['productos'];
      }
      return [];
    }
    throw Exception('Error al listar MIS productos (${response.statusCode})');
  }

  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Token no encontrado');
    }
    return token;
  }

  // ✅ Obtener productos públicos (todos, disponibles o no)
  static Future<List<dynamic>> listarProductosPublicos() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/productos'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);

      // Caso: { productos: [...] }
      if (decoded is Map && decoded['productos'] is List) {
        return decoded['productos'];
      }

      // Caso: lista directa
      if (decoded is List) {
        return decoded;
      }

      return [];
    }

    throw Exception('Error al listar productos (${response.statusCode})');
  }

  // ✅ Crear producto (con parámetros nombrados)
  static Future<void> crearProducto({
    required String nombre,
    required String descripcion,
    required String categoria,
    required double precio,
    required int stock,
    required int tiempoPreparacion,
  }) async {
    final token = await _getToken();

    debugPrint('📡 [ProductService] Creando producto...');
    debugPrint('  URL: ${AppConstants.baseUrl}/productos');
    debugPrint('  Token: ${token.substring(0, 20)}...');
    debugPrint('  Datos: nombre=$nombre, precio=$precio, stock=$stock');

    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/productos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'nombre': nombre,
        'descripcion': descripcion,
        'precio': precio,
        'categoria': categoria,
        'disponible': true,
        'tiempoPreparacion': tiempoPreparacion,
        'stock': stock,
      }),
    );

    debugPrint('📡 [ProductService] Response status: ${response.statusCode}');
    debugPrint('📡 [ProductService] Response body: ${response.body}');

    if (response.statusCode != 201 && response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al crear producto');
      } catch (_) {
        throw Exception(
          'Error al crear producto (${response.statusCode}): ${response.body}',
        );
      }
    }

    debugPrint('✅ [ProductService] Producto creado exitosamente');
  }

  // ✅ Eliminar producto
  static Future<void> eliminarProducto(dynamic id) async {
    final token = await _getToken();

    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/productos/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al eliminar producto');
      } catch (_) {
        throw Exception('Error al eliminar producto (${response.statusCode})');
      }
    }
  }

  // ✅ Cambiar disponibilidad (ON / OFF)  <-- AQUÍ AFUERA ✅
  static Future<void> cambiarDisponible({
    required dynamic id, // 👈 antes int
    required bool disponible,
  }) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/productos/$id/disponible'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'disponible': disponible}),
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al cambiar disponibilidad');
      } catch (_) {
        throw Exception(
          'Error al cambiar disponibilidad (${response.statusCode})',
        );
      }
    }
  }

  static Future<void> actualizarProducto({
    required dynamic id,
    required String nombre,
    required String descripcion,
    required double precio,
    required int stock,
    required int tiempoPreparacion,
  }) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/productos/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'nombre': nombre,
        'descripcion': descripcion,
        'precio': precio,
        'stock': stock,
        'tiempoPreparacion': tiempoPreparacion,
      }),
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al actualizar producto');
      } catch (_) {
        throw Exception(
          'Error al actualizar producto (${response.statusCode})',
        );
      }
    }
  }
}
