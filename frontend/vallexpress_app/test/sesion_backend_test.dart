// Prueba la sesión persistente de la app CONTRA EL BACKEND REAL (puerto 3000).
// Requisitos: backend levantado y el usuario "psesion" (clave secreto1) creado.
//   flutter test test/sesion_backend_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vallexpress_app/config/constants.dart';
import 'package:vallexpress_app/services/api_http.dart' as api;
import 'package:vallexpress_app/services/session_manager.dart';
import 'package:vallexpress_app/services/session_store.dart';

Future<Map<String, dynamic>> _login() async {
  final r = await http.post(
    Uri.parse('${AppConstants.baseUrl}/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': 'psesion', 'password': 'secreto1', 'dispositivo': 'Prueba Dart', 'plataforma': 'android'}),
  );
  expect(r.statusCode, 200, reason: r.body);
  return jsonDecode(r.body) as Map<String, dynamic>;
}

void main() {
  setUp(() {
    SessionStore.almacen = AlmacenMemoria();
    SessionStore.reiniciarCache();
  });

  test('login entrega token de acceso y refresh token, y se guardan', () async {
    final d = await _login();
    expect(d['token'], isNotEmpty);
    expect(d['refreshToken'], isNotEmpty);
    expect(d['expiresIn'], 900);
    await SessionManager.instance.guardarSesion(acceso: d['token'], refresh: d['refreshToken']);
    expect(await SessionStore.accessToken(), d['token']);
    expect(await SessionStore.refreshToken(), d['refreshToken']);
    expect(SessionStore.accesoVigente(d['token']), isTrue);
  });

  test('refrescar() rota el refresh token y entrega un token de acceso nuevo', () async {
    final d = await _login();
    await SessionManager.instance.guardarSesion(acceso: d['token'], refresh: d['refreshToken']);

    expect(await SessionManager.instance.refrescar(), isTrue);
    expect(await SessionStore.refreshToken(), isNot(d['refreshToken']), reason: 'el refresh token debe rotar');
    expect(await SessionStore.accessToken(), isNotEmpty);
  });

  test('dos renovaciones a la vez comparten UNA sola llamada (no se ve como robo)', () async {
    final d = await _login();
    await SessionManager.instance.guardarSesion(acceso: d['token'], refresh: d['refreshToken']);

    final resultados = await Future.wait([
      SessionManager.instance.refrescar(),
      SessionManager.instance.refrescar(),
      SessionManager.instance.refrescar(),
    ]);
    expect(resultados, [true, true, true]);
    // La sesión sigue viva: si se hubiera tomado como robo, esta renovación fallaría
    expect(await SessionManager.instance.refrescar(), isTrue);
  });

  test('una petición autenticada con el token de acceso VENCIDO se renueva sola y funciona', () async {
    final d = await _login();
    // Token "vencido" según el reloj local (exp en el pasado); el refresh token sí es válido
    final vencido = [
      base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', ''),
      base64Url.encode(utf8.encode('{"id":"psesion","exp":1}')).replaceAll('=', ''),
      'firma',
    ].join('.');
    await SessionStore.guardar(acceso: vencido, refresh: d['refreshToken']);

    // El servicio manda un token viejo a propósito: api_http debe usar el actual y renovarlo antes de enviar
    final r = await api.get(
      Uri.parse('${AppConstants.baseUrl}/auth/profile'),
      headers: {'Authorization': 'Bearer $vencido'},
    );
    expect(r.statusCode, 200, reason: r.body);
    expect(jsonDecode(r.body)['usuario']['id'], 'psesion');
    expect(await SessionStore.accessToken(), isNot(vencido));
  });

  test('cerrar la sesión en el servidor hace que el refresh token ya no sirva', () async {
    final d = await _login();
    await SessionManager.instance.guardarSesion(acceso: d['token'], refresh: d['refreshToken']);

    final fin = SessionManager.instance.sesionTerminada.first;
    final out = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/logout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': d['refreshToken']}),
    );
    expect(out.statusCode, 200);

    expect(await SessionManager.instance.refrescar(), isFalse);
    expect(await fin, 'SESIONCERRADA');
    expect(await SessionStore.refreshToken(), isNull, reason: 'al terminar la sesión se borra todo lo local');
  });

  test('sin sesión guardada, refrescar() devuelve false sin llamar al servidor', () async {
    expect(await SessionManager.instance.refrescar(), isFalse);
  });
}
