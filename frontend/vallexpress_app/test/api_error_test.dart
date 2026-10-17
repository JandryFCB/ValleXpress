// Los errores se muestran como mensajes para personas: nunca la ruta del servidor ni el error técnico.
//   flutter test test/api_error_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vallexpress_app/services/api_error.dart';

void main() {
  test('sin conexión: mensaje humano, sin "localhost" ni "errno"', () {
    final crudo = Exception('ClientException with SocketException: Connection refused (OS Error: Connection refused, errno = 111), address = localhost, port = 36480, uri=http://localhost:3000/api/auth/profile');
    final texto = textoDeError(crudo);
    expect(texto, ErrorConexion.sinConexion);
    expect(texto, isNot(contains('localhost')));
    expect(textoDeError(Exception('Error de conexión: ClientException: Failed host lookup')), ErrorConexion.sinConexion);
  });

  test('el servidor no responde a tiempo', () {
    expect(textoDeError(TimeoutException('x')), ErrorConexion.lento);
    expect(textoDeError(const ErrorConexion(ErrorConexion.lento)), ErrorConexion.lento);
  });

  test('los mensajes del servidor para el usuario se respetan', () {
    expect(textoDeError(Exception('El pedido mínimo de este negocio es \$5.00')), 'El pedido mínimo de este negocio es \$5.00');
  });

  test('errores del servidor (500) y demasiados intentos (429): sin códigos', () {
    expect(mensajeDeError(http.Response('{"error":"TypeError: cannot read x of undefined"}', 500), 'No se pudo'), contains('Tuvimos un problema'));
    expect(mensajeDeError(http.Response('', 429), 'No se pudo'), contains('Demasiados intentos'));
    expect(mensajeDeError(http.Response('<html>Bad Gateway</html>', 404), 'No se pudo cargar'), 'No se pudo cargar');
    expect(mensajeDeError(http.Response('{"error":"Dirección no encontrada"}', 404), 'x'), 'Dirección no encontrada');
  });
}
