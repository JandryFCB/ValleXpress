// Prueba la lógica de sesión con un servidor FALSO local (no necesita backend):
//   flutter test --dart-define=PUERTO=3555 test/sesion_logica_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/config/constants.dart';
import 'package:vallexpress_app/services/api_http.dart' as api;
import 'package:vallexpress_app/services/session_manager.dart';
import 'package:vallexpress_app/services/session_store.dart';

// JWT falso cuyo "exp" es en el futuro lejano: para el reloj local está vigente, así que la renovación
// preventiva NO actúa y se prueba el camino de "el servidor dijo TOKENEXPIRADO".
String _jwtVigente(String id) => [
      base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', ''),
      base64Url.encode(utf8.encode('{"id":"$id","exp":4102444800}')).replaceAll('=', ''),
      'firma',
    ].join('.');

class _Falso {
  late HttpServer servidor;
  final List<String> llamadas = [];
  final List<String?> tokensRecibidos = [];

  /// Qué responde /auth/refresh: 200 (rota), o un código de error
  String refresh = 'ok';
  int rotaciones = 0;

  Future<void> iniciar() async {
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, int.parse(const String.fromEnvironment('PUERTO', defaultValue: '3555')));
    servidor.listen((req) async {
      llamadas.add('${req.method} ${req.uri.path}');
      final cuerpo = await utf8.decoder.bind(req).join();
      Future<void> responder(int estado, Map<String, dynamic> datos) async {
        req.response.statusCode = estado;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(datos));
        await req.response.close();
      }

      if (req.uri.path.endsWith('/auth/refresh')) {
        expect(jsonDecode(cuerpo)['refreshToken'], isNotNull);
        switch (refresh) {
          case 'ok':
            rotaciones++;
            return responder(200, {'token': _jwtVigente('nuevo$rotaciones'), 'refreshToken': 'refresh-nuevo-$rotaciones-xxxxxxxxxxxxxxxx'});
          case 'expirado':
            return responder(401, {'success': false, 'error': 'La sesión expiró', 'code': 'REFRESHEXPIRADO'});
          case 'enuso':
            return responder(409, {'success': false, 'error': 'En uso', 'code': 'REFRESHENUSO'});
          default:
            return responder(500, {'success': false, 'error': 'boom', 'code': 'ERRORINTERNO'});
        }
      }

      // Ruta protegida de ejemplo
      final auth = req.headers.value('authorization');
      tokensRecibidos.add(auth);
      if (auth == 'Bearer ${_jwtVigente('viejo')}') {
        return responder(401, {'success': false, 'error': 'Token expirado', 'code': 'TOKENEXPIRADO'});
      }
      return responder(200, {'ok': true, 'auth': auth});
    });
  }

  Future<void> detener() => servidor.close(force: true);
}

void main() {
  late _Falso falso;
  Uri ruta(String p) => Uri.parse('${AppConstants.baseUrl}$p');

  setUp(() async {
    SessionStore.almacen = AlmacenMemoria();
    SessionStore.reiniciarCache();
    falso = _Falso();
    await falso.iniciar();
  });
  tearDown(() => falso.detener());

  test('401 TOKENEXPIRADO: renueva la sesión y REINTENTA la petición con el token nuevo (una sola vez)', () async {
    await SessionStore.guardar(acceso: _jwtVigente('viejo'), refresh: 'refresh-viejo-xxxxxxxxxxxxxxxxxxxx');

    final r = await api.get(ruta('/pedidos'), headers: {'Authorization': 'Bearer ${_jwtVigente('viejo')}'});

    expect(r.statusCode, 200);
    expect(jsonDecode(r.body)['auth'], 'Bearer ${_jwtVigente('nuevo1')}', reason: 'el reintento debe llevar el token renovado');
    expect(falso.llamadas, ['GET /api/pedidos', 'POST /api/auth/refresh', 'GET /api/pedidos']);
    expect(await SessionStore.refreshToken(), startsWith('refresh-nuevo-1'));
  });

  test('si la renovación falla porque la sesión terminó: borra todo, avisa a la app y devuelve el 401', () async {
    falso.refresh = 'expirado';
    await SessionStore.guardar(acceso: _jwtVigente('viejo'), refresh: 'refresh-viejo-xxxxxxxxxxxxxxxxxxxx');
    final aviso = SessionManager.instance.sesionTerminada.first;

    final r = await api.get(ruta('/pedidos'), headers: {'Authorization': 'Bearer ${_jwtVigente('viejo')}'});

    expect(r.statusCode, 401);
    expect(await aviso, 'REFRESHEXPIRADO');
    expect(await SessionStore.refreshToken(), isNull);
    expect(await SessionStore.accessToken(), isNull);
    expect(SessionManager.mensajeDe('REFRESHEXPIRADO'), contains('inactividad'));
  });

  test('un error del servidor (500) o REFRESHENUSO (409) NO cierran la sesión', () async {
    await SessionStore.guardar(acceso: _jwtVigente('viejo'), refresh: 'refresh-viejo-xxxxxxxxxxxxxxxxxxxx');
    for (final modo in ['enuso', 'error']) {
      falso.refresh = modo;
      expect(await SessionManager.instance.refrescar(), isFalse);
      expect(await SessionStore.refreshToken(), 'refresh-viejo-xxxxxxxxxxxxxxxxxxxx', reason: 'con "$modo" la sesión se conserva');
    }
  });

  test('SIN INTERNET la sesión no se cierra: refrescar() devuelve false y todo sigue guardado', () async {
    await SessionStore.guardar(acceso: _jwtVigente('viejo'), refresh: 'refresh-viejo-xxxxxxxxxxxxxxxxxxxx');
    await falso.detener(); // el servidor desaparece (como perder la red)

    expect(await SessionManager.instance.refrescar(), isFalse);
    expect(await SessionStore.refreshToken(), 'refresh-viejo-xxxxxxxxxxxxxxxxxxxx');
    expect(await SessionStore.accessToken(), _jwtVigente('viejo'));
    falso = _Falso()..servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // para el tearDown
  });

  test('peticiones SIN Authorization (login, registro...) pasan directo, sin tocar la sesión', () async {
    final r = await api.post(ruta('/auth/login'), headers: {'Content-Type': 'application/json'}, body: '{}');
    expect(r.statusCode, 200);
    expect(falso.llamadas, ['POST /api/auth/login']);
    expect(falso.tokensRecibidos.single, isNull);
  });

  test('accesoVigente: token válido, por vencer, vencido y basura', () {
    String conExp(int s) => [
          base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', ''),
          base64Url.encode(utf8.encode('{"exp":$s}')).replaceAll('=', ''),
          'f',
        ].join('.');
    final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(SessionStore.accesoVigente(conExp(ahora + 600)), isTrue);
    expect(SessionStore.accesoVigente(conExp(ahora + 10)), isFalse, reason: 'dentro del margen de 30 s se renueva antes');
    expect(SessionStore.accesoVigente(conExp(ahora - 10)), isFalse);
    expect(SessionStore.accesoVigente('basura'), isFalse);
    expect(SessionStore.accesoVigente(null), isFalse);
  });
}
