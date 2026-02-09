import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class VendedorService {
  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) throw Exception('Token no encontrado');
    return token;
  }

  // ===== OBTENER PERFIL DEL VENDEDOR =====
  static Future<Map<String, dynamic>> obtenerPerfilVendedor() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/vendedores/perfil/mi-negocio'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['vendedor'] != null) {
        return Map<String, dynamic>.from(data['vendedor']);
      }
      if (data is Map && data['data'] != null) {
        return Map<String, dynamic>.from(data['data']);
      }
      return Map<String, dynamic>.from(data);
    }

    throw Exception('Error al obtener perfil: ${response.statusCode}');
  }

  // ===== ACTUALIZAR PERFIL DEL VENDEDOR =====
  static Future<void> actualizarPerfilVendedor({
    required String nombreNegocio,
    required String categoria,
    required String descripcion,
    required String direccion,
    required String ciudad,
    required String telefono,
    required String horarioApertura,
    required String horarioCierre,
    required String diaDescanso,
  }) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/vendedores/perfil/actualizar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'nombreNegocio': nombreNegocio,
        'categoria': categoria,
        'descripcion': descripcion,
        'direccion': direccion,
        'ciudad': ciudad,
        'telefono': telefono,
        'horarioApertura': horarioApertura,
        'horarioCierre': horarioCierre,
        'diaDescanso': diaDescanso,
      }),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(
        body?['error'] ?? 'Error al actualizar perfil del vendedor',
      );
    }
  }

  // ===== OBTENER MIS PRODUCTOS =====
  static Future<List<Map<String, dynamic>>> obtenerMisProductos() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/productos/mis-productos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['productos'] is List) {
        return List<Map<String, dynamic>>.from(data['productos']);
      }
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    }

    throw Exception('Error al obtener productos: ${response.statusCode}');
  }

  // ===== CREAR PRODUCTO =====
  static Future<Map<String, dynamic>> crearProducto({
    required String nombre,
    required String descripcion,
    required double precio,
    required String categoria,
    required int tiempoPreparacion,
    required int stock,
  }) async {
    final token = await _getToken();

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

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['producto'] != null) {
        return Map<String, dynamic>.from(data['producto']);
      }
      return Map<String, dynamic>.from(data);
    }

    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    throw Exception(body?['error'] ?? 'Error al crear producto');
  }

  // ===== ACTUALIZAR PRODUCTO =====
  static Future<void> actualizarProducto({
    required int id,
    required String nombre,
    required String descripcion,
    required double precio,
    required String categoria,
    required int tiempoPreparacion,
    required int stock,
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
        'categoria': categoria,
        'tiempoPreparacion': tiempoPreparacion,
        'stock': stock,
      }),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al actualizar producto');
    }
  }

  // ===== CAMBIAR DISPONIBILIDAD DE PRODUCTO =====
  static Future<void> cambiarDisponibilidad({
    required int id,
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
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al cambiar disponibilidad');
    }
  }

  // ===== ELIMINAR PRODUCTO =====
  static Future<void> eliminarProducto(int id) async {
    final token = await _getToken();

    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/productos/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al eliminar producto');
    }
  }

  // ===== CONVERTIR XFILE A BASE64 =====
  static Future<String> xfileToBase64(XFile file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  // ===== ACTUALIZAR LOGO BASE64 =====
  static Future<void> actualizarLogoBase64(String base64Image) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/vendedores/perfil/logo'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'logo': base64Image}),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al actualizar logo');
    }
  }

  // ===== ACTUALIZAR BANNER BASE64 =====
  static Future<void> actualizarBannerBase64(String base64Image) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/vendedores/perfil/banner'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'banner': base64Image}),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al actualizar banner');
    }
  }

  // ===== ACTUALIZAR UBICACIÓN =====
  static Future<void> actualizarUbicacion({
    required double latitud,
    required double longitud,
  }) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/vendedores/perfil/ubicacion'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'latitud': latitud, 'longitud': longitud}),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al actualizar ubicación');
    }
  }
}
