import 'dart:async';
import 'dart:convert';
import 'api_http.dart' as http;

/// Saca el mensaje de error que mandó el servidor (`{ "error": "texto" }`) para mostrárselo al usuario.
/// Antes cada servicio hacía esto con un try/catch que se tragaba el mensaje real y mostraba uno genérico.
///
///     if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo guardar'));
String mensajeDeError(http.Response res, String porDefecto) {
  // Fallas del servidor: el usuario no tiene nada que corregir, así que no se le muestra el detalle técnico
  if (res.statusCode >= 500) return 'Tuvimos un problema en ValleXpress. Inténtalo de nuevo en unos minutos';
  if (res.statusCode == 429) return 'Demasiados intentos seguidos. Espera un momento y vuelve a intentarlo';
  try {
    final cuerpo = jsonDecode(res.body);
    if (cuerpo is Map) {
      final texto = cuerpo['error'] ?? cuerpo['message'];
      if (texto is String && texto.trim().isNotEmpty) return texto;
    }
  } catch (_) {
    // el cuerpo no era JSON: se usa el mensaje por defecto
  }
  return porDefecto;
}

/// Sin internet, servidor apagado o que no responde: el mensaje es para una persona, no para un programador
class ErrorConexion implements Exception {
  const ErrorConexion(this.mensaje);

  final String mensaje;

  static const sinConexion = 'No pudimos conectarnos con ValleXpress. Revisa tu internet o inténtalo en unos minutos';
  static const lento = 'ValleXpress está tardando en responder. Revisa tu conexión e inténtalo de nuevo';

  @override
  String toString() => mensaje;
}

// Restos técnicos que nunca deben verse en pantalla (vienen de servicios que arman su propio mensaje)
final _tecnico = RegExp(r'ClientException|SocketException|Connection (refused|reset|closed)|Failed host lookup|HandshakeException|XMLHttpRequest|errno|uri=', caseSensitive: false);

/// El texto de un error listo para mostrarlo en pantalla: sin "Exception: " ni detalles técnicos.
String textoDeError(Object e) {
  if (e is ErrorConexion) return e.mensaje;
  if (e is TimeoutException) return ErrorConexion.lento;
  if (e is FormatException) return 'Recibimos una respuesta inesperada. Inténtalo de nuevo';
  final texto = e.toString().replaceFirst('Exception: ', '').replaceFirst('Error de conexión: ', '').trim();
  if (_tecnico.hasMatch(texto)) return ErrorConexion.sinConexion;
  return texto.isEmpty ? 'Algo salió mal. Inténtalo de nuevo' : texto;
}
