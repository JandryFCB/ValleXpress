import 'dart:convert';
import '../config/constants.dart';
import '../models/telefono.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Teléfonos de la persona (GET/POST/PUT/PATCH/DELETE /api/telefonos). Hasta 5, uno solo principal, sin repetirse
/// entre personas. Los errores del servidor llegan con su mensaje real.
class TelefonoService {
  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Uri _url([String ruta = '']) => Uri.parse('${AppConstants.baseUrl}/telefonos$ruta');

  static Telefono _telefono(http.Response res) =>
      Telefono.desdeJson((jsonDecode(res.body) as Map<String, dynamic>)['telefono'] as Map<String, dynamic>);

  static Future<List<Telefono>> listar() async {
    final res = await http.get(_url(), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudieron cargar tus teléfonos'));
    final lista = (jsonDecode(res.body) as Map<String, dynamic>)['telefonos'] as List<dynamic>;
    return lista.map((t) => Telefono.desdeJson(t as Map<String, dynamic>)).toList();
  }

  static Future<Telefono> crear({required String numero, TipoTelefono tipo = TipoTelefono.movil, bool principal = false}) async {
    final res = await http.post(
      _url(),
      headers: await _cabeceras(),
      body: jsonEncode({'numero': numero, 'tipo': tipo.codigo, 'principal': principal}),
    );
    if (res.statusCode != 201) throw Exception(mensajeDeError(res, 'No se pudo guardar el teléfono'));
    return _telefono(res);
  }

  static Future<Telefono> actualizar(int id, {String? numero, TipoTelefono? tipo}) async {
    final res = await http.put(
      _url('/$id'),
      headers: await _cabeceras(),
      body: jsonEncode({if (numero != null) 'numero': numero, if (tipo != null) 'tipo': tipo.codigo}),
    );
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo actualizar el teléfono'));
    return _telefono(res);
  }

  static Future<Telefono> marcarPrincipal(int id) async {
    final res = await http.patch(_url('/$id/principal'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo cambiar el teléfono principal'));
    return _telefono(res);
  }

  static Future<void> eliminar(int id) async {
    final res = await http.delete(_url('/$id'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo eliminar el teléfono'));
  }
}
