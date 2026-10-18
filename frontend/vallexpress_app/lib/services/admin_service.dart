import 'dart:convert';
import '../config/constants.dart';
import '../models/admin.dart';
import '../models/documento_repartidor.dart';
import '../models/legal.dart';
import '../models/reputacion.dart';
import '../models/suscripcion.dart';
import '../models/pedido.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Panel del administrador (/api/admin): resumen, aprobaciones, pedidos, usuarios y configuración.
class AdminService {
  static Future<Map<String, String>> _cabeceras() async {
    final token = await SessionStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Tu sesión no está activa. Inicia sesión de nuevo.');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static Uri _url(String ruta, [Map<String, String?>? query]) {
    final q = {for (final e in (query ?? {}).entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('${AppConstants.baseUrl}/admin$ruta').replace(queryParameters: q.isEmpty ? null : q);
  }

  static Map<String, dynamic> _json(http.Response res, String error) {
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, error));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Pagina<T> _pagina<T>(Map<String, dynamic> datos, String clave, T Function(Map<String, dynamic>) leer) => Pagina(
        (datos[clave] as List).map((e) => leer(Map<String, dynamic>.from(e))).toList(),
        hayMas: datos['pagination']?['hasNext'] == true,
        total: (datos['pagination']?['total'] as num?)?.toInt() ?? 0,
      );

  /// Movimientos detrás de una cifra del resumen (pedidos, ventas, ganancia, envios, encurso, enlinea)
  static Future<DetalleCifra> detalleCifra(String tipo, {String rango = 'hoy'}) async =>
      DetalleCifra.desdeJson(_json(await http.get(_url('/resumen/$tipo', {'rango': rango}), headers: await _cabeceras()), 'No se pudo cargar el detalle'));

  static Future<ResumenAdmin> resumen() async =>
      ResumenAdmin.desdeJson(_json(await http.get(_url('/resumen'), headers: await _cabeceras()), 'No se pudo cargar el resumen'));

  // --- Negocios y repartidores ---
  static Future<Pagina<NegocioAdmin>> negocios({String? aprobacion, String? busqueda, int pagina = 1}) async {
    final res = await http.get(_url('/negocios', {'aprobacion': aprobacion, 'q': busqueda?.trim(), 'page': '$pagina'}), headers: await _cabeceras());
    return _pagina(_json(res, 'No se pudieron cargar los negocios'), 'negocios', NegocioAdmin.desdeJson);
  }

  /// estado: 'aprobado' | 'rechazado' | 'suspendido' | 'pendiente'. Rechazar o suspender exige el motivo.
  static Future<NegocioAdmin> aprobacionNegocio(int id, String estado, {String? motivo}) async {
    final res = await http.patch(_url('/negocios/$id/aprobacion'), headers: await _cabeceras(), body: jsonEncode({'estado': estado, if (motivo != null) 'motivo': motivo}));
    return NegocioAdmin.desdeJson(Map<String, dynamic>.from(_json(res, 'No se pudo cambiar la aprobación')['negocio']));
  }

  static Future<Pagina<RepartidorAdmin>> repartidores({String? aprobacion, String? busqueda, int pagina = 1}) async {
    final res = await http.get(_url('/repartidores', {'aprobacion': aprobacion, 'q': busqueda?.trim(), 'page': '$pagina'}), headers: await _cabeceras());
    return _pagina(_json(res, 'No se pudieron cargar los repartidores'), 'repartidores', RepartidorAdmin.desdeJson);
  }

  static Future<RepartidorAdmin> aprobacionRepartidor(String usuario, String estado, {String? motivo}) async {
    final res = await http.patch(_url('/repartidores/$usuario/aprobacion'), headers: await _cabeceras(), body: jsonEncode({'estado': estado, if (motivo != null) 'motivo': motivo}));
    return RepartidorAdmin.desdeJson(Map<String, dynamic>.from(_json(res, 'No se pudo cambiar la aprobación')['repartidor']));
  }

  // --- Pedidos ---
  /// estado: 'activos' | 'historial' | null (todos)
  static Future<Pagina<Pedido>> pedidos({String? estado, int pagina = 1}) async {
    final res = await http.get(_url('/pedidos', {'estado': estado, 'page': '$pagina'}), headers: await _cabeceras());
    return _pagina(_json(res, 'No se pudieron cargar los pedidos'), 'pedidos', Pedido.desdeJson);
  }

  static Future<Pedido> pedido(int id) async =>
      Pedido.desdeJson(Map<String, dynamic>.from(_json(await http.get(_url('/pedidos/$id'), headers: await _cabeceras()), 'No se pudo cargar el pedido')['pedido']));

  static Future<Pedido> cancelarPedido(int id, String motivo) async {
    final res = await http.patch(_url('/pedidos/$id/cancelar'), headers: await _cabeceras(), body: jsonEncode({'motivo': motivo.trim()}));
    return Pedido.desdeJson(Map<String, dynamic>.from(_json(res, 'No se pudo cancelar el pedido')['pedido']));
  }

  // --- Usuarios ---
  static Future<Pagina<UsuarioAdmin>> usuarios({String? rol, String? busqueda, int pagina = 1}) async {
    final res = await http.get(_url('/usuarios', {'rol': rol, 'q': busqueda?.trim(), 'page': '$pagina'}), headers: await _cabeceras());
    return _pagina(_json(res, 'No se pudieron cargar los usuarios'), 'usuarios', UsuarioAdmin.desdeJson);
  }

  /// Bloquear (activo = false) exige el motivo; se cierran todas sus sesiones.
  static Future<UsuarioAdmin> cambiarEstadoUsuario(String usuario, {required bool activo, String? motivo}) async {
    final res = await http.patch(_url('/usuarios/$usuario/estado'), headers: await _cabeceras(), body: jsonEncode({'activo': activo, if (motivo != null) 'motivo': motivo}));
    return UsuarioAdmin.desdeJson(Map<String, dynamic>.from(_json(res, 'No se pudo cambiar el estado de la cuenta')['usuario']));
  }

  static UsuarioAdmin _usuario(http.Response res, String error) => UsuarioAdmin.desdeJson(Map<String, dynamic>.from(_json(res, error)['usuario']));

  static Future<UsuarioAdmin> usuario(String usuario) async => _usuario(await http.get(_url('/usuarios/$usuario'), headers: await _cabeceras()), 'No se pudo cargar la cuenta');

  /// Crea una cuenta de cualquier rol. datos: nombre, apellido, email, cedula, telefono, password, rol y, según el rol,
  /// nombreNegocio/categoriaNegocio (vendedor) o vehiculo/placa/color (repartidor).
  static Future<UsuarioAdmin> crearUsuario(Map<String, dynamic> datos) async {
    final res = await http.post(_url('/usuarios'), headers: await _cabeceras(), body: jsonEncode(datos));
    if (res.statusCode != 201) throw Exception(mensajeDeError(res, 'No se pudo crear la cuenta'));
    return UsuarioAdmin.desdeJson(Map<String, dynamic>.from(jsonDecode(res.body)['usuario']));
  }

  static Future<UsuarioAdmin> editarUsuario(String usuario, Map<String, dynamic> cambios) async =>
      _usuario(await http.put(_url('/usuarios/$usuario'), headers: await _cabeceras(), body: jsonEncode(cambios)), 'No se pudieron guardar los cambios');

  static Future<UsuarioAdmin> ponerClave(String usuario, String clave) async =>
      _usuario(await http.put(_url('/usuarios/$usuario/clave'), headers: await _cabeceras(), body: jsonEncode({'clave': clave})), 'No se pudo cambiar la contraseña');

  static Future<UsuarioAdmin> fotoUsuario(String usuario, String base64) async =>
      _usuario(await http.put(_url('/usuarios/$usuario/foto'), headers: await _cabeceras(), body: jsonEncode({'imagen': base64})), 'No se pudo subir la foto');

  /// Dar de baja: la cuenta queda inactiva (no se borra su historial) y se puede reactivar
  static Future<UsuarioAdmin> darDeBaja(String usuario, String motivo) async =>
      _usuario(await http.delete(_url('/usuarios/$usuario'), headers: await _cabeceras(), body: jsonEncode({'motivo': motivo})), 'No se pudo dar de baja la cuenta');

  /// Documentos que subió un repartidor (para revisarlos antes de aprobarlo)
  static Future<DocumentosRepartidor> documentosRepartidor(String usuario) async =>
      DocumentosRepartidor.desdeJson(_json(await http.get(_url('/repartidores/$usuario/documentos'), headers: await _cabeceras()), 'No se pudieron cargar los documentos'));

  static Future<RepartidorAdmin> editarRepartidor(String usuario, {required String vehiculo, String? placa, String? color}) async {
    final res = await http.put(_url('/repartidores/$usuario'), headers: await _cabeceras(), body: jsonEncode({'vehiculo': vehiculo, 'placa': placa, 'color': color}));
    return RepartidorAdmin.desdeJson(Map<String, dynamic>.from(_json(res, 'No se pudo guardar el vehículo')['repartidor']));
  }

  /// Documentos legales vigentes y cuántas cuentas activas ya aceptaron esa versión
  static Future<List<({DocumentoLegal documento, int cuentas, int aceptaron})>> legal() async {
    final j = _json(await http.get(_url('/legal'), headers: await _cabeceras()), 'No se pudieron cargar los documentos');
    return [
      for (final d in (j['documentos'] as List))
        (documento: DocumentoLegal.desdeJson(Map<String, dynamic>.from(d)), cuentas: (d['cuentas'] as num?)?.toInt() ?? 0, aceptaron: (d['aceptaron'] as num?)?.toInt() ?? 0),
    ];
  }

  // --- Suscripción mensual de vendedores y repartidores ---
  static Future<({ConfigSuscripcion config, List<ComprobantePorRevisar> comprobantes, List<Suscriptor> suscriptores})> suscripciones() async {
    final j = _json(await http.get(_url('/suscripciones'), headers: await _cabeceras()), 'No se pudieron cargar las suscripciones');
    return (
      config: ConfigSuscripcion.desdeJson(Map<String, dynamic>.from(j['config'] ?? {})),
      comprobantes: (j['comprobantes'] as List? ?? []).map((c) => ComprobantePorRevisar.desdeJson(Map<String, dynamic>.from(c))).toList(),
      suscriptores: (j['suscriptores'] as List? ?? []).map((c) => Suscriptor.desdeJson(Map<String, dynamic>.from(c))).toList(),
    );
  }

  static Future<EstadoSuscripcion> suscripcionDe(String usuario) async =>
      EstadoSuscripcion.desdeJson(_json(await http.get(_url('/suscripciones/$usuario'), headers: await _cabeceras()), 'No se pudo cargar la suscripción'));

  /// Pago en efectivo o transferencia sin comprobante. mes = AAAA-MM-01
  static Future<EstadoSuscripcion> registrarPagoSuscripcion(String usuario, String mes, {String? referencia}) async {
    final res = await http.post(_url('/suscripciones/$usuario/pagos'), headers: await _cabeceras(), body: jsonEncode({'mes': mes, if (referencia != null && referencia.trim().isNotEmpty) 'referencia': referencia.trim()}));
    if (res.statusCode != 201) throw Exception(mensajeDeError(res, 'No se pudo registrar el pago'));
    return EstadoSuscripcion.desdeJson(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
  }

  static Future<ConfigSuscripcion> guardarConfigSuscripcion(Map<String, Object> cambios) async => ConfigSuscripcion.desdeJson(Map<String, dynamic>.from(
      _json(await http.put(_url('/suscripciones/config'), headers: await _cabeceras(), body: jsonEncode(cambios)), 'No se pudo guardar la configuración del cobro')['config']));

  static Future<EstadoSuscripcion> aprobarComprobante(int id) async =>
      EstadoSuscripcion.desdeJson(_json(await http.post(_url('/comprobantes/$id/aprobar'), headers: await _cabeceras()), 'No se pudo aprobar el comprobante'));

  static Future<EstadoSuscripcion> rechazarComprobante(int id, String motivo) async => EstadoSuscripcion.desdeJson(
      _json(await http.post(_url('/comprobantes/$id/rechazar'), headers: await _cabeceras(), body: jsonEncode({'motivo': motivo})), 'No se pudo rechazar el comprobante'));

  // --- Reputación y advertencias del repartidor ---
  static Future<Reputacion> reputacionRepartidor(String usuario) async =>
      Reputacion.desdeJson(_json(await http.get(_url('/repartidores/$usuario/reputacion'), headers: await _cabeceras()), 'No se pudo cargar la reputación'));

  static Future<Reputacion> advertirRepartidor(String usuario, String motivo) async {
    final res = await http.post(_url('/repartidores/$usuario/advertencias'), headers: await _cabeceras(), body: jsonEncode({'motivo': motivo}));
    if (res.statusCode != 201) throw Exception(mensajeDeError(res, 'No se pudo enviar la advertencia'));
    return Reputacion.desdeJson(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
  }

  // --- Zona de servicio ---
  static Future<Map<String, dynamic>> zona() async => Map<String, dynamic>.from(_json(await http.get(_url('/zona'), headers: await _cabeceras()), 'No se pudo cargar la zona')['zona']);

  static Future<Map<String, dynamic>> guardarZona(Map<String, Object> cambios) async =>
      Map<String, dynamic>.from(_json(await http.put(_url('/zona'), headers: await _cabeceras(), body: jsonEncode(cambios)), 'No se pudo guardar la zona')['zona']);

  // --- Tarifas: envío por distancia ---
  static Future<Map<String, double>> tarifas() async {
    final res = await http.get(_url('/tarifas'), headers: await _cabeceras());
    return _aTarifas(_json(res, 'No se pudieron cargar las tarifas')['tarifas']);
  }

  static Future<Map<String, double>> guardarTarifas(Map<String, double> cambios) async {
    final res = await http.put(_url('/tarifas'), headers: await _cabeceras(), body: jsonEncode(cambios));
    return _aTarifas(_json(res, 'No se pudieron guardar las tarifas')['tarifas']);
  }

  static Map<String, double> _aTarifas(Object? j) => Map<String, dynamic>.from(j as Map).map((k, v) => MapEntry(k, (v as num).toDouble()));

  // --- Perfiles y permisos ---
  static Future<List<PerfilPermisos>> perfiles() async {
    final res = await http.get(_url('/perfiles'), headers: await _cabeceras());
    return (_json(res, 'No se pudieron cargar los perfiles')['perfiles'] as List).map((p) => PerfilPermisos.desdeJson(Map<String, dynamic>.from(p))).toList();
  }

  /// Cambia los permisos de un perfil. Con [aprobarPendientes] también aprueba las solicitudes que esperaban
  /// (cada una recibe su aviso y su correo); devuelve cuántas aprobó.
  static Future<({PerfilPermisos perfil, int aprobados})> cambiarPerfil(String rol, {bool? registroAbierto, bool? aprobacionAutomatica, bool aprobarPendientes = false}) async {
    final res = await http.patch(
      _url('/perfiles/$rol'),
      headers: await _cabeceras(),
      body: jsonEncode({
        if (registroAbierto != null) 'registroAbierto': registroAbierto,
        if (aprobacionAutomatica != null) 'aprobacionAutomatica': aprobacionAutomatica,
        if (aprobarPendientes) 'aprobarPendientes': true,
      }),
    );
    final datos = _json(res, 'No se pudo guardar el permiso');
    return (perfil: PerfilPermisos.desdeJson(Map<String, dynamic>.from(datos['perfil'])), aprobados: (datos['aprobados'] as num?)?.toInt() ?? 0);
  }
}
