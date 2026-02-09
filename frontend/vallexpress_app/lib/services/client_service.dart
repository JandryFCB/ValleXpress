import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/mock_data.dart';

class ClientService {
  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) throw Exception('Token no encontrado');
    return token;
  }

  // ===== OBTENER MIS PEDIDOS =====
  static Future<List<Map<String, dynamic>>> obtenerMisPedidos() async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/pedidos/mis-pedidos'),
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

      // Fallback a mock data
      return MockData.obtenerPedidosPorUsuario(1);
    } catch (e) {
      print('Error obteniendo mis pedidos: $e');
      return MockData.obtenerPedidosPorUsuario(1);
    }
  }

  // ===== OBTENER DETALLE DE PEDIDO =====
  static Future<Map<String, dynamic>> obtenerDetallePedido(int pedidoId) async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['pedido'] != null) {
          return Map<String, dynamic>.from(data['pedido']);
        }
        return Map<String, dynamic>.from(data);
      }

      // Fallback a mock data
      final pedido = MockData.obtenerPedidoPorId(pedidoId);
      return pedido ?? {};
    } catch (e) {
      print('Error obteniendo detalle pedido: $e');
      final pedido = MockData.obtenerPedidoPorId(pedidoId);
      return pedido ?? {};
    }
  }

  // ===== CREAR PEDIDO =====
  static Future<Map<String, dynamic>> crearPedido({
    required int vendedorId,
    required List<Map<String, dynamic>> detalles,
    required String direccionEntrega,
    String notasEspeciales = '',
  }) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/pedidos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'vendedorId': vendedorId,
        'detalles': detalles,
        'direccionEntrega': direccionEntrega,
        'notasEspeciales': notasEspeciales,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['pedido'] != null) {
        return Map<String, dynamic>.from(data['pedido']);
      }
      return Map<String, dynamic>.from(data);
    }

    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    throw Exception(body?['error'] ?? 'Error al crear pedido');
  }

  // ===== CANCELAR PEDIDO =====
  static Future<void> cancelarPedido(int pedidoId) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/cancelar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al cancelar pedido');
    }
  }

  // ===== CALIFICAR PEDIDO =====
  static Future<void> calificarPedido({
    required int pedidoId,
    required int valoracion,
    required String comentario,
  }) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/calificar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'valoracion': valoracion,
        'comentario': comentario,
      }),
    );

    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      throw Exception(body?['error'] ?? 'Error al calificar pedido');
    }
  }

  // ===== OBTENER PRODUCTOS DE VENDEDOR =====
  static Future<List<Map<String, dynamic>>> obtenerProductosVendedor(
      int vendedorId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/productos/vendedor/$vendedorId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['productos'] is List) {
          return List<Map<String, dynamic>>.from(data['productos']);
        }
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }

      // Fallback a mock data
      return MockData.obtenerProductosPorVendedor(vendedorId);
    } catch (e) {
      print('Error obteniendo productos del vendedor: $e');
      return MockData.obtenerProductosPorVendedor(vendedorId);
    }
  }

  // ===== OBTENER TODOS LOS PRODUCTOS =====
  static Future<List<Map<String, dynamic>>> obtenerTodosProductos() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/productos'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['productos'] is List) {
          return List<Map<String, dynamic>>.from(data['productos']);
        }
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }

      return MockData.productosMock;
    } catch (e) {
      print('Error obteniendo productos: $e');
      return MockData.productosMock;
    }
  }

  // ===== OBTENER TODOS LOS VENDEDORES =====
  static Future<List<Map<String, dynamic>>> obtenerTodosVendedores() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/vendedores'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['vendedores'] is List) {
          return List<Map<String, dynamic>>.from(data['vendedores']);
        }
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }

      return [MockData.vendedorMock, MockData.vendedorMock2];
    } catch (e) {
      print('Error obteniendo vendedores: $e');
      return [MockData.vendedorMock, MockData.vendedorMock2];
    }
  }
}
