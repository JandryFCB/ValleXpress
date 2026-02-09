import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class RepartidorPedidosService {
  // Obtener pedidos pendientes (no asignados)
  static Future<List<dynamic>> obtenerPedidosPendientes() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/repartidores/pendientes'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['pedidos'] ?? [];
    }
    throw Exception(
      'Error al obtener pedidos pendientes (${response.statusCode})',
    );
  }

  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Token no encontrado');
    }
    return token;
  }

  // ✅ Obtener MIS pedidos asignados (repartidor)
  static Future<List<dynamic>> obtenerPedidos() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/repartidores/mis-pedidos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['pedidos'] ?? [];
    }

    throw Exception('Error al obtener pedidos (${response.statusCode})');
  }

  // ✅ Aceptar pedido y asignar precio de delivery
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

    if (response.statusCode != 200) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['error'] ?? 'Error al aceptar pedido');
    }

    final decoded = jsonDecode(response.body);
    return decoded['pedido']; // aquí ya viene con total actualizado
  }

  static Future<dynamic> aceptarPedidoOld(
    String pedidoId,
    double costoDelivery,
  ) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse(
        '${AppConstants.baseUrl}/repartidores/pedidos/$pedidoId/aceptar',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'costoDelivery': costoDelivery}),
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al aceptar pedido');
      } catch (_) {
        throw Exception('Error al aceptar pedido (${response.statusCode})');
      }
    }

    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }

  // ✅ Actualizar estado del pedido (repartidor)
  static Future<dynamic> cambiarEstado(String pedidoId, String estado) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse(
        '${AppConstants.baseUrl}/repartidores/pedidos/$pedidoId/estado',
      ),
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

  // ✅ Obtener todos los pedidos aceptados por vendedores (para vista del repartidor)
  static Future<List<dynamic>> obtenerPedidosVista() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/repartidores/pedidos-vista'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['pedidos'] ?? [];
    }

    throw Exception(
      'Error al obtener pedidos para vista (${response.statusCode})',
    );
  }
}
