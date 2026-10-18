import 'dart:convert';
import '../config/constants.dart';
import '../models/suscripcion.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Suscripción mensual del vendedor o el repartidor (/api/suscripcion): su estado de cuenta y subir el comprobante.
class SuscripcionService {
  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Uri _url(String ruta) => Uri.parse('${AppConstants.baseUrl}/suscripcion$ruta');

  static EstadoSuscripcion _estado(http.Response res, int esperado, String error) {
    if (res.statusCode != esperado) throw Exception(mensajeDeError(res, error));
    return EstadoSuscripcion.desdeJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<EstadoSuscripcion> estado() async => _estado(await http.get(_url(''), headers: await _cabeceras()), 200, 'No se pudo cargar tu suscripción');

  /// Sube la foto del comprobante de un mes (AAAA-MM-01). El administrador lo revisa.
  static Future<EstadoSuscripcion> subirComprobante({required String mes, required String imagen, String? referencia}) async => _estado(
        await http.post(
          _url('/comprobante'),
          headers: await _cabeceras(),
          body: jsonEncode({'mes': mes, 'imagen': imagen, if (referencia != null && referencia.trim().isNotEmpty) 'referencia': referencia.trim()}),
        ),
        201,
        'No se pudo enviar el comprobante',
      );
}
