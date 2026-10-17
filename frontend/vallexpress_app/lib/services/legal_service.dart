import 'dart:convert';
import '../config/constants.dart';
import '../models/legal.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Términos y condiciones y política de privacidad. El texto vive en el servidor (con su versión): si se publica
/// una versión nueva, al entrar a la app se pide aceptarla otra vez.
class LegalService {
  static Uri _url(String ruta) => Uri.parse('${AppConstants.baseUrl}/legal$ruta');

  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// Página web pública del documento (la misma que se publica en Google Play)
  static String urlWeb(String id) => '${AppConstants.serverUrl}/legal/$id';

  /// El documento completo, para leerlo (no necesita sesión: se ve también desde el registro)
  static Future<DocumentoLegal> documento(String id) async {
    final res = await http.get(_url('/$id'));
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo cargar el documento'));
    return DocumentoLegal.desdeJson(Map<String, dynamic>.from(jsonDecode(res.body)['documento']));
  }

  /// Documentos cuya versión vigente el usuario todavía no aceptó
  static Future<List<DocumentoLegal>> pendientes() async {
    final res = await http.get(_url('/pendientes'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo revisar los términos'));
    return (jsonDecode(res.body)['pendientes'] as List).map((d) => DocumentoLegal.desdeJson(Map<String, dynamic>.from(d))).toList();
  }

  /// Acepta esas versiones. Devuelve lo que siga pendiente (vacío si todo quedó aceptado).
  static Future<List<DocumentoLegal>> aceptar(List<DocumentoLegal> documentos) async {
    final res = await http.post(
      _url('/aceptar'),
      headers: await _cabeceras(),
      body: jsonEncode({
        'documentos': [for (final d in documentos) {'id': d.id, 'version': d.version}],
        'plataforma': 'app',
      }),
    );
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo guardar tu aceptación'));
    return (jsonDecode(res.body)['pendientes'] as List).map((d) => DocumentoLegal.desdeJson(Map<String, dynamic>.from(d))).toList();
  }
}
