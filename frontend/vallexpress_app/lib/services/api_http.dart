import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as base;
import 'api_error.dart';
import 'session_manager.dart';
import 'session_store.dart';

// Cliente HTTP de la app con sesión persistente. Los servicios lo importan en lugar de package:http:
//
//     import 'api_http.dart' as http;      // en vez de: import 'package:http/http.dart' as http;
//
// y siguen usando http.get / http.post / http.put / http.patch / http.delete igual que antes (los demás tipos,
// como http.Response, se re-exportan). Lo que cambia por dentro, SOLO en las peticiones que llevan Authorization:
//   1. Se usa siempre el token de acceso más reciente (si estaba por vencer, se renueva antes de enviar).
//   2. Si el servidor responde 401 TOKENEXPIRADO, se renueva la sesión con el refresh token y se REINTENTA una vez.
// Así el usuario no ve nunca el vencimiento de los 15 minutos.
//   3. Ninguna petición espera para siempre (límite de tiempo) y si no hay conexión o el servidor no responde se
//      lanza ErrorConexion con un mensaje humano, nunca el error técnico con la ruta del servidor.
export 'package:http/http.dart' hide get, post, put, patch, delete;

Future<base.Response> get(Uri url, {Map<String, String>? headers}) => _enviar('GET', url, headers);

Future<base.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar('POST', url, headers, body: body, encoding: encoding);

Future<base.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar('PUT', url, headers, body: body, encoding: encoding);

Future<base.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar('PATCH', url, headers, body: body, encoding: encoding);

Future<base.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar('DELETE', url, headers, body: body, encoding: encoding);

bool _llevaAuth(Map<String, String>? h) => h?.keys.any((k) => k.toLowerCase() == 'authorization') ?? false;

// Las consultas responden rápido; las que suben datos (fotos en base64) pueden tardar más con mala señal
Duration _limite(String metodo) => metodo == 'GET' ? const Duration(seconds: 20) : const Duration(seconds: 45);

Future<base.Response> _enviar(String metodo, Uri url, Map<String, String>? headers, {Object? body, Encoding? encoding}) async {
  try {
    return await _enviarSinCapturar(metodo, url, headers, body: body, encoding: encoding).timeout(_limite(metodo));
  } on TimeoutException {
    throw const ErrorConexion(ErrorConexion.lento);
  } on base.ClientException {
    throw const ErrorConexion(ErrorConexion.sinConexion);
  }
}

Future<base.Response> _enviarSinCapturar(String metodo, Uri url, Map<String, String>? headers, {Object? body, Encoding? encoding}) async {
  Future<base.Response> intento(Map<String, String>? h) {
    switch (metodo) {
      case 'POST':
        return base.post(url, headers: h, body: body, encoding: encoding);
      case 'PUT':
        return base.put(url, headers: h, body: body, encoding: encoding);
      case 'PATCH':
        return base.patch(url, headers: h, body: body, encoding: encoding);
      case 'DELETE':
        return base.delete(url, headers: h, body: body, encoding: encoding);
      default:
        return base.get(url, headers: h);
    }
  }

  Map<String, String>? conToken(String? token) =>
      token == null ? headers : {...?headers, 'Authorization': 'Bearer $token'};

  final autenticada = _llevaAuth(headers);
  if (!autenticada) return intento(headers);

  // El servicio pudo haber leído un token viejo: se usa el actual, y si ya venció se renueva antes de enviar
  var token = await SessionStore.accessToken();
  if (token != null && !SessionStore.accesoVigente(token)) {
    if (await SessionManager.instance.refrescar()) token = await SessionStore.accessToken();
  }

  var respuesta = await intento(conToken(token));

  if (respuesta.statusCode == 401 && _esExpirado(respuesta)) {
    if (await SessionManager.instance.refrescar()) {
      respuesta = await intento(conToken(await SessionStore.accessToken()));
    }
  }
  return respuesta;
}

bool _esExpirado(base.Response r) {
  try {
    final cuerpo = jsonDecode(r.body);
    return cuerpo is Map && cuerpo['code'] == 'TOKENEXPIRADO';
  } catch (_) {
    return false;
  }
}
