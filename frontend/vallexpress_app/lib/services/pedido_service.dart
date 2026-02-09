import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class PedidoService {
  // Repartidor acepta pedido y asigna delivery
  static Future<dynamic> aceptarPedidoRepartidor({
    required String pedidoId,
    required double costoDelivery,
  }) async {
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

  // Repartidor marca pedido en camino
  static Future<dynamic> marcarEnCamino(String pedidoId) async {
    final token = await _getToken();
    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/en-camino'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al marcar en camino');
      } catch (_) {
        throw Exception('Error al marcar en camino (${response.statusCode})');
      }
    }
    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }

  // Repartidor marca pedido como recogido
  static Future<dynamic> marcarRecogido(String pedidoId) async {
    final token = await _getToken();
    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/recogido'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al marcar recogido');
      } catch (_) {
        throw Exception('Error al marcar recogido (${response.statusCode})');
      }
    }
    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }

  // Repartidor marca pedido entregado

  static Future<dynamic> marcarEntregado(String pedidoId) async {
    final token = await _getToken();
    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/entregado'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al marcar entregado');
      } catch (_) {
        throw Exception('Error al marcar entregado (${response.statusCode})');
      }
    }
    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }

  // Cliente marca pedido recibido
  static Future<dynamic> marcarRecibidoCliente(String pedidoId) async {
    final token = await _getToken();
    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/recibido'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al marcar recibido');
      } catch (_) {
        throw Exception('Error al marcar recibido (${response.statusCode})');
      }
    }
    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }

  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Token no encontrado');
    }
    return token;
  }

  // ✅ Crear pedido (soporta UUID string y múltiples productos)
  static Future<dynamic> crearPedido({
    required String vendedorId,
    required List<Map<String, dynamic>> productos,
    required String metodoPago,
    String? notasCliente,
    String? direccionEntregaId, // 👈 opcional: usar tabla direcciones
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
        'productos': productos,
        'metodoPago': metodoPago,
        'notasCliente': notasCliente,
        if (direccionEntregaId != null)
          'direccionEntregaId': direccionEntregaId,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al crear pedido');
      } catch (_) {
        throw Exception('Error al crear pedido (${response.statusCode})');
      }
    }

    final decoded = jsonDecode(response.body);
    return decoded['pedido'];
  }

  // ✅ Obtener MIS pedidos (cliente)
  static Future<List<dynamic>> misPedidos() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/pedidos/mis-pedidos'),
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

  // ✅ Obtener pedido por ID
  static Future<dynamic> obtenerPorId(String pedidoId) async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // El backend devuelve el pedido directamente, no dentro de { pedido: ... }
      return decoded;
    }

    throw Exception('Error al obtener pedido (${response.statusCode})');
  }

  // ✅ Actualizar estado (vendedor o repartidor)
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

  // ✅ Cancelar pedido (cliente)
  static Future<void> cancelarPedido(String pedidoId) async {
    final token = await _getToken();

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/pedidos/$pedidoId/cancelar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al cancelar pedido');
      } catch (_) {
        throw Exception('Error al cancelar pedido (${response.statusCode})');
      }
    }
  }

  // ✅ Obtener notificaciones del usuario
  static Future<List<dynamic>> obtenerNotificaciones() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/notificaciones'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // El backend devuelve { notificaciones: [...] }
      if (decoded is Map && decoded['notificaciones'] is List) {
        return List<dynamic>.from(decoded['notificaciones']);
      }
      // Fallback si es array directo
      if (decoded is List) {
        return decoded;
      }
      return [];
    }

    throw Exception('Error al obtener notificaciones (${response.statusCode})');
  }

  // ✅ Marcar notificación como leída
  static Future<void> marcarNotificacionLeida(String notificacionId) async {
    final token = await _getToken();

    final response = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/notificaciones/$notificacionId/leida'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['error'] ?? 'Error al marcar notificación');
      } catch (_) {
        throw Exception(
          'Error al marcar notificación (${response.statusCode})',
        );
      }
    }
  }
}
