import 'dart:convert';
import 'api_http.dart' as http;

/// Saca el mensaje de error que mandó el servidor (`{ "error": "texto" }`) para mostrárselo al usuario.
/// Antes cada servicio hacía esto con un try/catch que se tragaba el mensaje real y mostraba uno genérico.
///
///     if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo guardar'));
String mensajeDeError(http.Response res, String porDefecto) {
  try {
    final cuerpo = jsonDecode(res.body);
    if (cuerpo is Map) {
      final texto = cuerpo['error'] ?? cuerpo['message'];
      if (texto is String && texto.trim().isNotEmpty) return texto;
    }
  } catch (_) {
    // el cuerpo no era JSON: se usa el mensaje por defecto
  }
  return '$porDefecto (${res.statusCode})';
}

/// Quita el prefijo "Exception: " de un error para mostrarlo en pantalla.
String textoDeError(Object e) => e.toString().replaceFirst('Exception: ', '').trim();
