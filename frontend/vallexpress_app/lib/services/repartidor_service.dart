import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../config/constants.dart';
import '../models/mock_data.dart';

class RepartidorService {
  // ===== SUBIR FOTO DE PERFIL DEL REPARTIDOR =====
  static Future<String?> subirFotoPerfil(XFile imageFile) async {
    final token = await _getToken();

    // Convertir imagen a base64
    final base64 = await xfileToBase64(imageFile);

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/repartidores/perfil/foto'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'foto': base64}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['foto'] as String?;
    } else {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al subir foto de perfil');
    }
  }

  // ===== CONVERTIR XFILE A BASE64 =====
  static Future<String> xfileToBase64(XFile file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) throw Exception('Token no encontrado');
    return token;
  }

  // ===== OBTENER PERFIL DEL REPARTIDOR =====
  static Future<Map<String, dynamic>> obtenerPerfilRepartidor() async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/repartidores/perfil/mi-perfil'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['repartidor'] != null) {
          return Map<String, dynamic>.from(data['repartidor']);
        }
        if (data is Map && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
        return Map<String, dynamic>.from(data);
      }

      // Fallback a mock data
      return MockData.repartidoresMock.isNotEmpty
          ? MockData.repartidoresMock[0]
          : {};
    } catch (e) {
      print('Error obteniendo perfil repartidor: $e');
      return MockData.repartidoresMock.isNotEmpty
          ? MockData.repartidoresMock[0]
          : {};
    }
  }

  // ===== ACTUALIZAR PERFIL DEL REPARTIDOR =====
  static Future<void> actualizarPerfilRepartidor({
    required String estado,
    required String vehiculo,
    required String placa,
  }) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/repartidores/perfil/actualizar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'estado': estado,
        'vehiculo': vehiculo,
        'placa': placa,
      }),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(
        body?['error'] ?? 'Error al actualizar perfil del repartidor',
      );
    }
  }

  // ===== OBTENER PEDIDOS DISPONIBLES =====
  static Future<List<Map<String, dynamic>>> obtenerPedidosDisponibles() async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/repartidores/pedidos-disponibles'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['pedidos'] is List) {
          return List<Map<String, dynamic>>.from(data['pedidos']);
        }
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }

      return MockData.pedidosMock;
    } catch (e) {
      print('Error obteniendo pedidos disponibles: $e');
      return MockData.pedidosMock;
    }
  }

  // ===== ACEPTAR PEDIDO =====
  static Future<dynamic> aceptarPedido(
    String pedidoId,
    double costoDelivery,
  ) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/aceptar-repartidor'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'costoDelivery': costoDelivery}),
    );

    Map<String, dynamic> decoded = {};
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}

    if (response.statusCode != 200) {
      throw Exception(
        decoded['error'] ?? 'Error al aceptar pedido (${response.statusCode})',
      );
    }

    return decoded['pedido'];
  }

  // ===== MARCAR EN CAMINO =====
  static Future<void> marcarEnCamino(String pedidoId) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/en-camino'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['error'] ?? 'Error al marcar en camino');
    }
  }

  // ===== MARCAR ENTREGADO =====
  static Future<void> marcarEntregado(String pedidoId) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/entregado'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['error'] ?? 'Error al marcar entregado');
    }
  }

  // ===== OBTENER MIS ENTREGAS ACTIVAS =====
  static Future<List<Map<String, dynamic>>> obtenerEntregasActivas() async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/repartidores/entregas-activas'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['entregas'] is List) {
          return List<Map<String, dynamic>>.from(data['entregas']);
        }
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }

      return [];
    } catch (e) {
      print('Error obteniendo entregas activas: $e');
      return [];
    }
  }

  // ===== CAMBIAR ESTADO DE DISPONIBILIDAD =====
  static Future<void> cambiarEstado(String nuevoEstado) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/repartidores/estado'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'estado': nuevoEstado}),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al cambiar estado');
    }
  }

  // ===== CAMBIAR DISPONIBILIDAD =====
  static Future<void> cambiarDisponibilidad(bool disponible) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/repartidores/disponibilidad'),
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

  // ===== OBTENER UBICACIÓN ACTUAL DE UN REPARTIDOR =====
  static Future<Map<String, dynamic>?> obtenerUbicacionRepartidor(
    String repartidorId,
  ) async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse(
          '${AppConstants.baseUrl}/repartidores/$repartidorId/ubicacion',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Map<String, dynamic>.from(data);
      } else {
        return null;
      }
    } catch (e) {
      print('Error obteniendo ubicación del repartidor: $e');
      return null;
    }
  }
}
