import 'dart:convert';
import '../config/constants.dart';
import '../models/documento_repartidor.dart';
import '../models/pedido.dart';
import '../models/reputacion.dart';
import '../models/repartidor.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Pedidos: del cliente (/api/pedidos), del negocio (/api/mi-negocio/pedidos), del repartidor (/api/repartidor)
/// y avisos (/api/notificaciones). Reemplaza a los servicios viejos de pedidos, vendedor y repartidor.
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

  /// Cuánto cuesta el envío de un negocio a una dirección (lo calcula ValleXpress por distancia) y si está dentro
  /// de su área de entrega. El carrito lo muestra antes de pedir.
  static Future<({double costoEnvio, double? distanciaKm, bool fueraDeCobertura, double radioKm})> cotizar({required int negocioId, required int direccionId}) async {
    final res = await http.get(_url('/pedidos/cotizar', {'negocioId': '$negocioId', 'direccionId': '$direccionId'}), headers: await _cabeceras());
    final j = _json(res, 200, 'No se pudo calcular el envío');
    return (
      costoEnvio: (j['costoEnvio'] as num).toDouble(),
      distanciaKm: (j['distanciaKm'] as num?)?.toDouble(),
      fueraDeCobertura: j['fueraDeCobertura'] == true,
      radioKm: (j['radioKm'] as num?)?.toDouble() ?? 0,
    );
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

  static Future<Pedido> calificarRepartidor(int id, {required int puntuacion, String? comentario}) async => _pedido(
        await http.post(
          _url('/pedidos/$id/calificar'),
          headers: await _cabeceras(),
          body: jsonEncode({'puntuacion': puntuacion, 'destino': 'repartidor', if (comentario != null && comentario.trim().isNotEmpty) 'comentario': comentario.trim()}),
        ),
        'No se pudo guardar tu calificación',
      );

  // -------------------------------------------------------------------------------------------
  // Pedidos de mi negocio (vendedor)
  // -------------------------------------------------------------------------------------------
  /// El negocio califica al repartidor que se llevó el pedido (desde que lo recoge)
  static Future<Pedido> calificarRepartidorComoNegocio(int id, {required int puntuacion, String? comentario}) async => _pedido(
        await http.post(
          _url('/mi-negocio/pedidos/$id/calificar-repartidor'),
          headers: await _cabeceras(),
          body: jsonEncode({'puntuacion': puntuacion, if (comentario != null && comentario.trim().isNotEmpty) 'comentario': comentario.trim()}),
        ),
        'No se pudo guardar tu calificación',
      );

  static Future<({List<Pedido> pedidos, bool hayMas})> pedidosDelNegocio({String? estado, int pagina = 1}) async {
    final res = await http.get(_url('/mi-negocio/pedidos', {if (estado != null) 'estado': estado, 'page': '$pagina'}), headers: await _cabeceras());
    final datos = _json(res, 200, 'No se pudieron cargar los pedidos');
    final lista = (datos['pedidos'] as List).map((p) => Pedido.desdeJson(Map<String, dynamic>.from(p))).toList();
    return (pedidos: lista, hayMas: datos['pagination']?['hasNext'] == true);
  }

  /// estado: 'confirmado' | 'preparando' | 'listo' | 'rechazado'
  static Future<Pedido> cambiarEstadoNegocio(int id, String estado, {String? motivo, int? tiempoEstimado}) async => _pedido(
        await http.patch(
          _url('/mi-negocio/pedidos/$id/estado'),
          headers: await _cabeceras(),
          body: jsonEncode({'estado': estado, if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(), if (tiempoEstimado != null) 'tiempoEstimado': tiempoEstimado}),
        ),
        'No se pudo cambiar el estado del pedido',
      );

  // -------------------------------------------------------------------------------------------
  // Repartidor
  // -------------------------------------------------------------------------------------------
  static PerfilRepartidor _perfil(http.Response res, [int esperado = 200]) =>
      PerfilRepartidor.desdeJson(_json(res, esperado, 'No se pudo cargar tu perfil de repartidor')['repartidor'] as Map<String, dynamic>);

  /// Mi perfil de repartidor, o null si aún no lo tengo
  static Future<PerfilRepartidor?> miPerfilRepartidor() async {
    final res = await http.get(_url('/repartidor'), headers: await _cabeceras());
    if (res.statusCode == 404) return null;
    return _perfil(res);
  }

  static Future<PerfilRepartidor> guardarVehiculo({required Vehiculo vehiculo, String? placa, String? color, bool crear = false}) async {
    final cuerpo = jsonEncode({'vehiculo': vehiculo.codigo, 'placa': vehiculo.llevaPlaca ? placa : null, 'color': color});
    final res = crear
        ? await http.post(_url('/repartidor'), headers: await _cabeceras(), body: cuerpo)
        : await http.put(_url('/repartidor'), headers: await _cabeceras(), body: cuerpo);
    return _perfil(res, crear ? 201 : 200);
  }

  /// Rechazado → vuelve a revisión (después de corregir el vehículo o la placa)
  /// Documentos que pide la verificación (cédula, selfie y, si el vehículo lleva placa, licencia y matrícula)
  /// Lo que opinan de mí clientes y negocios, y las advertencias del administrador
  static Future<Reputacion> miReputacion() async => Reputacion.desdeJson(_json(await http.get(_url('/repartidor/reputacion'), headers: await _cabeceras()), 200, 'No se pudo cargar tu reputación'));

  static Future<DocumentosRepartidor> misDocumentos() async =>
      DocumentosRepartidor.desdeJson(_json(await http.get(_url('/repartidor/documentos'), headers: await _cabeceras()), 200, 'No se pudieron cargar tus documentos'));

  /// Sube (o reemplaza) la foto de un documento
  static Future<DocumentosRepartidor> subirDocumento(String tipo, String imagen) async => DocumentosRepartidor.desdeJson(
      _json(await http.put(_url('/repartidor/documentos/$tipo'), headers: await _cabeceras(), body: jsonEncode({'imagen': imagen})), 200, 'No se pudo subir el documento'));

  static Future<PerfilRepartidor> pedirRevisionRepartidor() async => _perfil(await http.post(_url('/repartidor/revision'), headers: await _cabeceras()));

  static Future<PerfilRepartidor> cambiarDisponibilidad(bool disponible) async =>
      _perfil(await http.patch(_url('/repartidor/disponibilidad'), headers: await _cabeceras(), body: jsonEncode({'disponible': disponible})));

  static Future<PedidosLibres> pedidosLibres() async {
    final res = await http.get(_url('/repartidor/pedidos/libres'), headers: await _cabeceras());
    return PedidosLibres.desdeJson(_json(res, 200, 'No se pudieron cargar los pedidos disponibles'));
  }

  static Future<({List<Pedido> pedidos, bool hayMas})> misEntregas({String? estado, int pagina = 1}) async {
    final res = await http.get(_url('/repartidor/pedidos', {if (estado != null) 'estado': estado, 'page': '$pagina'}), headers: await _cabeceras());
    final datos = _json(res, 200, 'No se pudieron cargar tus entregas');
    final lista = (datos['pedidos'] as List).map((p) => Pedido.desdeJson(Map<String, dynamic>.from(p))).toList();
    return (pedidos: lista, hayMas: datos['pagination']?['hasNext'] == true);
  }

  static Future<Pedido> aceptarPedido(int id) async =>
      _pedido(await http.patch(_url('/repartidor/pedidos/$id/aceptar'), headers: await _cabeceras()), 'No se pudo aceptar el pedido');

  static Future<Pedido> marcarRecogido(int id) async =>
      _pedido(await http.patch(_url('/repartidor/pedidos/$id/recogido'), headers: await _cabeceras()), 'No se pudo marcar como recogido');

  static Future<Pedido> marcarEntregado(int id) async =>
      _pedido(await http.patch(_url('/repartidor/pedidos/$id/entregado'), headers: await _cabeceras()), 'No se pudo marcar como entregado');

  /// Respaldo por HTTP cuando el socket no está conectado
  static Future<void> enviarUbicacion(double latitud, double longitud) async {
    await http.put(_url('/repartidor/ubicacion'), headers: await _cabeceras(), body: jsonEncode({'latitud': latitud, 'longitud': longitud}));
  }

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
