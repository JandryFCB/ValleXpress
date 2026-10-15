import 'dart:convert';
import '../config/constants.dart';
import '../models/pedido.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Pedidos del cliente (/api/pedidos) y avisos (/api/notificaciones).
/// Reemplaza al servicio viejo pedido_service.
class PedidosService {
  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Uri _url(String ruta, [Map<String, String>? query]) =>
      Uri.parse('${AppConstants.baseUrl}$ruta').replace(queryParameters: (query == null || query.isEmpty) ? null : query);

  static Map<String, dynamic> _json(http.Response res, int esperado, String error) {
    if (res.statusCode != esperado) throw Exception(mensajeDeError(res, error));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Pedido _pedido(http.Response res, String error, [int esperado = 200]) =>
      Pedido.desdeJson(_json(res, esperado, error)['pedido'] as Map<String, dynamic>);

  // -------------------------------------------------------------------------------------------
  // Pedidos
  // -------------------------------------------------------------------------------------------
  static Future<List<MetodoPago>> metodosPago() async {
    final res = await http.get(_url('/pedidos/metodos-pago'), headers: await _cabeceras());
    final lista = _json(res, 200, 'No se pudieron cargar los métodos de pago')['metodos'] as List;
    return lista.map((m) => MetodoPago.desdeJson(Map<String, dynamic>.from(m))).toList();
  }

  /// Hace el pedido. Los precios y el total los calcula el servidor.
  static Future<Pedido> crear({
    required int negocioId,
    required int direccionId,
    required String metodoPago,
    required List<Map<String, dynamic>> productos,
    String? notas,
  }) async =>
      _pedido(
        await http.post(
          _url('/pedidos'),
          headers: await _cabeceras(),
          body: jsonEncode({
            'negocioId': negocioId,
            'direccionId': direccionId,
            'metodoPago': metodoPago,
            'productos': productos,
            if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
          }),
        ),
        'No se pudo hacer el pedido',
        201,
      );

  /// estado: 'activos' | 'historial' (null = todos)
  static Future<({List<Pedido> pedidos, bool hayMas})> misPedidos({String? estado, int pagina = 1}) async {
    final res = await http.get(_url('/pedidos/mis-pedidos', {if (estado != null) 'estado': estado, 'page': '$pagina'}), headers: await _cabeceras());
    final datos = _json(res, 200, 'No se pudieron cargar tus pedidos');
    final lista = (datos['pedidos'] as List).map((p) => Pedido.desdeJson(Map<String, dynamic>.from(p))).toList();
    return (pedidos: lista, hayMas: datos['pagination']?['hasNext'] == true);
  }

  static Future<Pedido> obtener(int id) async => _pedido(await http.get(_url('/pedidos/$id'), headers: await _cabeceras()), 'No se pudo cargar el pedido');

  static Future<Pedido> cancelar(int id, {String? motivo}) async => _pedido(
        await http.patch(_url('/pedidos/$id/cancelar'), headers: await _cabeceras(), body: jsonEncode({if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim()})),
        'No se pudo cancelar el pedido',
      );

  static Future<Pedido> confirmarRecibido(int id) async =>
      _pedido(await http.patch(_url('/pedidos/$id/recibido'), headers: await _cabeceras()), 'No se pudo confirmar el pedido');

  static Future<Pedido> calificar(int id, {required int puntuacion, String? comentario}) async => _pedido(
        await http.post(
          _url('/pedidos/$id/calificar'),
          headers: await _cabeceras(),
          body: jsonEncode({'puntuacion': puntuacion, if (comentario != null && comentario.trim().isNotEmpty) 'comentario': comentario.trim()}),
        ),
        'No se pudo guardar tu calificación',
      );

  // -------------------------------------------------------------------------------------------
  // Avisos (notificaciones)
  // -------------------------------------------------------------------------------------------
  static Future<({List<Aviso> avisos, int noLeidas, bool hayMas})> avisos({int pagina = 1}) async {
    final res = await http.get(_url('/notificaciones', {'pagina': '$pagina', 'limite': '30'}), headers: await _cabeceras());
    final datos = _json(res, 200, 'No se pudieron cargar tus avisos');
    final lista = (datos['notificaciones'] as List).map((n) => Aviso.desdeJson(Map<String, dynamic>.from(n))).toList();
    return (avisos: lista, noLeidas: (datos['noLeidas'] as num?)?.toInt() ?? 0, hayMas: datos['hayMas'] == true);
  }

  static Future<int> avisosNoLeidos() async {
    final res = await http.get(_url('/notificaciones/no-leidas'), headers: await _cabeceras());
    return (_json(res, 200, 'No se pudo consultar tus avisos')['noLeidas'] as num?)?.toInt() ?? 0;
  }

  static Future<void> marcarAvisoLeido(int id) async {
    final res = await http.patch(_url('/notificaciones/$id/leida'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo marcar el aviso'));
  }

  static Future<void> marcarTodosLeidos() async {
    final res = await http.patch(_url('/notificaciones/leer-todas'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudieron marcar los avisos'));
  }
}
