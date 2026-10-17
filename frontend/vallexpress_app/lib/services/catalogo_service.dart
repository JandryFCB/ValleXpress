import 'dart:convert';
import '../config/constants.dart';
import '../models/liquidacion.dart';
import '../models/negocio.dart';
import '../models/producto.dart';
import 'api_error.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

/// Catálogo: negocios y productos.
///   * Público (cualquier usuario):  /api/negocios
///   * Del vendedor (su negocio):     /api/mi-negocio
/// Reemplaza a los servicios viejos vendedor_service y product_service.
class CatalogoService {
  /// Negocio que el administrador está gestionando (null = el vendedor gestiona el suyo).
  static int? _gestionando;

  // Las rutas de gestión son las mismas para el vendedor y para el administrador; cambia solo la base
  static String get _base => _gestionando == null ? '/mi-negocio' : '/admin/negocios/$_gestionando/gestion';

  /// El administrador abre las pantallas del vendedor (Mi negocio, productos, horario) sobre otro negocio:
  ///     await CatalogoService.gestionarComoAdmin(negocioId, () => Navigator.push(...));
  /// Mientras la acción no termina, todas las llamadas de "mi negocio" van a ese negocio.
  static Future<T> gestionarComoAdmin<T>(int negocioId, Future<T> Function() accion) async {
    _gestionando = negocioId;
    try {
      return await accion();
    } finally {
      _gestionando = null;
    }
  }

  static bool get gestionandoComoAdmin => _gestionando != null;

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

  static Negocio _negocio(http.Response res, [int esperado = 200]) =>
      Negocio.desdeJson(_json(res, esperado, 'No se pudo cargar el negocio')['negocio'] as Map<String, dynamic>);

  static Producto _producto(http.Response res, [int esperado = 200]) =>
      Producto.desdeJson(_json(res, esperado, 'No se pudo guardar el producto')['producto'] as Map<String, dynamic>);

  // -------------------------------------------------------------------------------------------
  // Público
  // -------------------------------------------------------------------------------------------
  static Future<List<Categoria>> categorias() async {
    final res = await http.get(_url('/negocios/categorias'), headers: await _cabeceras());
    final lista = _json(res, 200, 'No se pudieron cargar las categorías')['categorias'] as List;
    return lista.map((c) => Categoria.desdeJson(Map<String, dynamic>.from(c))).toList();
  }

  static Future<({List<Negocio> negocios, bool hayMas})> negocios({String? categoria, String? busqueda, bool soloAbiertos = false, int pagina = 1}) async {
    final res = await http.get(
      _url('/negocios', {
        if (categoria != null) 'categoria': categoria,
        if (busqueda != null && busqueda.trim().isNotEmpty) 'q': busqueda.trim(),
        if (soloAbiertos) 'abiertos': 'true',
        'page': '$pagina',
      }),
      headers: await _cabeceras(),
    );
    final datos = _json(res, 200, 'No se pudieron cargar los negocios');
    final lista = (datos['negocios'] as List).map((n) => Negocio.desdeJson(Map<String, dynamic>.from(n))).toList();
    return (negocios: lista, hayMas: (datos['pagination']?['hasNext']) == true);
  }

  static Future<Negocio> negocio(int id) async => _negocio(await http.get(_url('/negocios/$id'), headers: await _cabeceras()));

  static Future<Menu> menu(int negocioId) async {
    final res = await http.get(_url('/negocios/$negocioId/productos'), headers: await _cabeceras());
    return Menu.desdeJson(_json(res, 200, 'No se pudo cargar el menú'));
  }

  // -------------------------------------------------------------------------------------------
  // Mi negocio (vendedor)
  // -------------------------------------------------------------------------------------------
  /// El negocio del vendedor, o null si todavía no tiene uno
  static Future<Negocio?> miNegocio() async {
    final res = await http.get(_url(_base), headers: await _cabeceras());
    if (res.statusCode == 404) return null;
    return _negocio(res);
  }

  static Future<Negocio> crearNegocio({required String nombre, required String categoria, String? descripcion}) async => _negocio(
        await http.post(_url(_base), headers: await _cabeceras(), body: jsonEncode({'nombre': nombre, 'categoria': categoria, 'descripcion': descripcion})),
        201,
      );

  /// Mi estado de cuenta con ValleXpress: semanas, comisión por pagar y a dónde transferir (solo el dueño)
  static Future<EstadoDeCuenta> misLiquidaciones() async =>
      EstadoDeCuenta.desdeJson(_json(await http.get(_url('/mi-negocio/liquidaciones'), headers: await _cabeceras()), 200, 'No se pudo cargar tu estado de cuenta'));

  /// Sube la foto del comprobante de transferencia de una semana (el administrador lo revisa)
  static Future<EstadoDeCuenta> subirComprobante({required String semana, required String imagen, String? referencia}) async {
    final res = await http.post(
      _url('/mi-negocio/liquidaciones/comprobante'),
      headers: await _cabeceras(),
      body: jsonEncode({'semana': semana, 'imagen': imagen, if (referencia != null && referencia.trim().isNotEmpty) 'referencia': referencia.trim()}),
    );
    return EstadoDeCuenta.desdeJson(_json(res, 201, 'No se pudo enviar el comprobante'));
  }

  /// Rechazado → vuelve a revisión (después de corregir los datos). Solo el dueño, no el administrador.
  static Future<Negocio> pedirRevisionNegocio() async => _negocio(await http.post(_url('/mi-negocio/revision'), headers: await _cabeceras()));

  static Future<Negocio> actualizarNegocio(Map<String, dynamic> cambios) async =>
      _negocio(await http.put(_url(_base), headers: await _cabeceras(), body: jsonEncode(cambios)));

  static Future<Negocio> fijarLocal({required String direccion, String? referencia, required double latitud, required double longitud}) async => _negocio(
        await http.put(
          _url('$_base/local'),
          headers: await _cabeceras(),
          body: jsonEncode({'direccion': direccion, 'referencia': referencia, 'latitud': latitud, 'longitud': longitud}),
        ),
      );

  static Future<Negocio> fijarHorarios(List<HorarioDia> horarios) async => _negocio(
        await http.put(_url('$_base/horarios'), headers: await _cabeceras(), body: jsonEncode({'horarios': horarios.map((h) => h.aJson()).toList()})),
      );

  static Future<Negocio> cambiarEstado({bool? abierto, bool? aceptaPedidos}) async => _negocio(
        await http.patch(
          _url('$_base/estado'),
          headers: await _cabeceras(),
          body: jsonEncode({if (abierto != null) 'abierto': abierto, if (aceptaPedidos != null) 'aceptaPedidos': aceptaPedidos}),
        ),
      );

  /// tipo: 'logo' | 'portada'. La imagen va en base64.
  static Future<Negocio> subirImagenNegocio(String tipo, String base64) async =>
      _negocio(await http.put(_url('$_base/$tipo'), headers: await _cabeceras(), body: jsonEncode({'imagen': base64})));

  // -------------------------------------------------------------------------------------------
  // Productos de mi negocio
  // -------------------------------------------------------------------------------------------
  static Future<Menu> misProductos() async {
    final res = await http.get(_url('$_base/productos'), headers: await _cabeceras());
    return Menu.desdeJson(_json(res, 200, 'No se pudieron cargar tus productos'));
  }

  static Future<Producto> crearProducto(Map<String, dynamic> datos) async =>
      _producto(await http.post(_url('$_base/productos'), headers: await _cabeceras(), body: jsonEncode(datos)), 201);

  static Future<Producto> actualizarProducto(int id, Map<String, dynamic> cambios) async =>
      _producto(await http.put(_url('$_base/productos/$id'), headers: await _cabeceras(), body: jsonEncode(cambios)));

  static Future<Producto> cambiarEstadoProducto(int id, EstadoProducto estado) async =>
      _producto(await http.patch(_url('$_base/productos/$id/estado'), headers: await _cabeceras(), body: jsonEncode({'estado': estado.codigo})));

  static Future<Producto> fijarStock(int id, int stock) async =>
      _producto(await http.patch(_url('$_base/productos/$id/stock'), headers: await _cabeceras(), body: jsonEncode({'stock': stock})));

  static Future<Producto> subirImagenProducto(int id, String base64) async =>
      _producto(await http.put(_url('$_base/productos/$id/imagen'), headers: await _cabeceras(), body: jsonEncode({'imagen': base64})));

  static Future<void> eliminarProducto(int id) async {
    final res = await http.delete(_url('$_base/productos/$id'), headers: await _cabeceras());
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo eliminar el producto'));
  }
}
