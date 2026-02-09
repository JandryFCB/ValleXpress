import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class VendedorPedidosService {
  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Token no encontrado');
    }
    return token;
  }

  // ✅ Obtener mis pedidos (vendedor)
  static Future<List<dynamic>> misPedidos() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/pedidos/vendedor/pedidos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded as List<dynamic>;
    }

    throw Exception('Error al obtener pedidos (${response.statusCode})');
  }

  // ✅ Actualizar estado del pedido (vendedor)
  static Future<dynamic> actualizarEstado({
    required String pedidoId,
    required String estado,
  }) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/estado'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'estado': estado}),
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al actualizar estado');
      } catch (_) {
        throw Exception('Error al actualizar estado (${response.statusCode})');
      }
    }

    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }
}
