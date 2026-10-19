import 'dart:convert';
import '../config/constants.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Un mensaje de "Ayúdanos a mejorar ValleXpress". usuario/nombre/rol solo llegan al administrador.
class Sugerencia {
  const Sugerencia({required this.id, required this.tipo, required this.mensaje, required this.estado, this.satisfaccion, this.respuesta, this.fecha, this.usuario, this.nombre, this.rol, this.versionApp});

  final int id;
  final String tipo; // sugerencia | problema | felicitacion
  final String mensaje;
  final String estado; // nueva | leida | atendida
  final int? satisfaccion;
  final String? respuesta;
  final DateTime? fecha;
  final String? usuario;
  final String? nombre;
  final String? rol;
  final String? versionApp;

  factory Sugerencia.desdeJson(Map<String, dynamic> j) => Sugerencia(
        id: (j['id'] as num).toInt(),
        tipo: '${j['tipo'] ?? 'sugerencia'}',
        mensaje: '${j['mensaje'] ?? ''}',
        estado: '${j['estado'] ?? 'nueva'}',
        satisfaccion: (j['satisfaccion'] as num?)?.toInt(),
        respuesta: j['respuesta']?.toString(),
        fecha: j['fecha'] == null ? null : DateTime.tryParse('${j['fecha']}')?.toLocal(),
        usuario: j['usuario']?.toString(),
        nombre: j['nombre']?.toString(),
        rol: j['rol']?.toString(),
        versionApp: j['versionApp']?.toString(),
      );
}

class SugerenciaService {
  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Future<Sugerencia> enviar({required String tipo, required String mensaje, int? satisfaccion, String? versionApp}) async {
    final res = await http.post(
      Uri.parse('${AppConstants.baseUrl}/sugerencias'),
      headers: await _cabeceras(),
      body: jsonEncode({'tipo': tipo, 'mensaje': mensaje.trim(), if (satisfaccion != null) 'satisfaccion': satisfaccion, if (versionApp != null) 'versionApp': versionApp}),
    );
    if (res.statusCode != 201) throw Exception(mensajeDeError(res, 'No pudimos enviar tu mensaje'));
    return Sugerencia.desdeJson(Map<String, dynamic>.from(jsonDecode(res.body)['sugerencia'] as Map));
  }

  static Future<List<Sugerencia>> mias() async {
    final res = await http.get(Uri.parse('${AppConstants.baseUrl}/sugerencias/mias'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No pudimos cargar tus mensajes'));
    return [for (final s in (jsonDecode(res.body)['sugerencias'] as List)) Sugerencia.desdeJson(Map<String, dynamic>.from(s as Map))];
  }

  // --- Administrador ---
  static Future<({List<Sugerencia> lista, Map<String, int> conteos, double? satisfaccion})> todas({String? estado}) async {
    final res = await http.get(Uri.parse('${AppConstants.baseUrl}/admin/sugerencias').replace(queryParameters: estado == null ? null : {'estado': estado}), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudieron cargar las sugerencias'));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      lista: [for (final s in (j['sugerencias'] as List)) Sugerencia.desdeJson(Map<String, dynamic>.from(s as Map))],
      conteos: {for (final e in Map<String, dynamic>.from(j['conteos'] ?? {}).entries) e.key: (e.value as num).toInt()},
      satisfaccion: (j['satisfaccionPromedio'] as num?)?.toDouble(),
    );
  }

  static Future<Sugerencia> atender(int id, {String? estado, String? respuesta}) async {
    final res = await http.patch(
      Uri.parse('${AppConstants.baseUrl}/admin/sugerencias/$id'),
      headers: await _cabeceras(),
      body: jsonEncode({if (estado != null) 'estado': estado, if (respuesta != null) 'respuesta': respuesta}),
    );
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo guardar'));
    return Sugerencia.desdeJson(Map<String, dynamic>.from(jsonDecode(res.body)['sugerencia'] as Map));
  }
}
