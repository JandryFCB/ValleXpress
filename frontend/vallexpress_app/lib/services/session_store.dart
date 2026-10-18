import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dónde se guardan los tokens de la sesión. En la app es almacenamiento CIFRADO (Keystore de Android / Keychain
/// de iOS); en las pruebas se cambia por una versión en memoria.
abstract class AlmacenTokens {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
}

class AlmacenCifrado implements AlmacenTokens {
  static const FlutterSecureStorage _s = FlutterSecureStorage();

  @override
  Future<String?> leer(String clave) => _s.read(key: clave);
  @override
  Future<void> escribir(String clave, String valor) => _s.write(key: clave, value: valor);
  @override
  Future<void> borrar(String clave) => _s.delete(key: clave);
}

class AlmacenMemoria implements AlmacenTokens {
  final Map<String, String> _datos = {};

  @override
  Future<String?> leer(String clave) async => _datos[clave];
  @override
  Future<void> escribir(String clave, String valor) async => _datos[clave] = valor;
  @override
  Future<void> borrar(String clave) async => _datos.remove(clave);
}

/// Sesión persistente (como Uber o Rappi): el servidor entrega un token de ACCESO corto (15 min) y un REFRESH TOKEN
/// largo (90 días sin usar la app). El refresh token es la llave de la sesión: por eso vive en almacenamiento
/// cifrado y nunca en SharedPreferences.
class SessionStore {
  static AlmacenTokens almacen = AlmacenCifrado();

  static const String _kAcceso = 'sesion_acceso';
  static const String _kRefresh = 'sesion_refresh';

  // Copia en memoria para no leer el almacén cifrado en cada petición
  static String? _acceso;
  static String? _refresh;
  static bool _cargado = false;

  static Future<void> _cargar() async {
    if (_cargado) return;
    _acceso = await almacen.leer(_kAcceso);
    _refresh = await almacen.leer(_kRefresh);
    _cargado = true;
  }

  static Future<void> guardar({required String acceso, required String refresh}) async {
    _acceso = acceso;
    _refresh = refresh;
    _cargado = true;
    await almacen.escribir(_kAcceso, acceso);
    await almacen.escribir(_kRefresh, refresh);
  }

  static Future<String?> accessToken() async {
    await _cargar();
    return _acceso;
  }

  static Future<String?> refreshToken() async {
    await _cargar();
    return _refresh;
  }

  /// Borra la sesión (cierre de sesión o sesión terminada por el servidor)
  static Future<void> limpiar() async {
    _acceso = null;
    _refresh = null;
    _cargado = true;
    await almacen.borrar(_kAcceso);
    await almacen.borrar(_kRefresh);
  }

  /// Fuerza a releer del almacén (solo para pruebas)
  static void reiniciarCache() {
    _acceso = null;
    _refresh = null;
    _cargado = false;
  }

  /// ¿El token de acceso sigue vigente? Se lee el "exp" del JWT sin verificar la firma (eso lo hace el servidor);
  /// sirve solo para decidir si conviene renovarlo ANTES de usarlo. [margen] evita enviar uno a punto de vencer.
  static bool accesoVigente(String? jwt, {Duration margen = const Duration(seconds: 30)}) {
    if (jwt == null) return false;
    try {
      final partes = jwt.split('.');
      if (partes.length != 3) return false;
      final carga = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
      final exp = carga['exp'];
      if (exp is! num) return false;
      final vence = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return vence.isAfter(DateTime.now().add(margen));
    } catch (_) {
      return false;
    }
  }
}

/// Una cuenta con sesión abierta en este celular que no es la que se está usando (una persona puede tener cuenta de
/// cliente, de negocio y de repartidor). Se guarda su refresh token para volver a ella sin escribir la contraseña.
class CuentaGuardada {
  const CuentaGuardada({required this.usuario, required this.tipoUsuario, required this.nombre, required this.email, required this.refresh});

  final String usuario;
  final String tipoUsuario;
  final String nombre;
  final String email;
  final String refresh;

  Map<String, String> aJson() => {'usuario': usuario, 'tipoUsuario': tipoUsuario, 'nombre': nombre, 'email': email, 'refresh': refresh};

  factory CuentaGuardada.desdeJson(Map<String, dynamic> j) => CuentaGuardada(
        usuario: '${j['usuario']}',
        tipoUsuario: '${j['tipoUsuario'] ?? 'cliente'}',
        nombre: '${j['nombre'] ?? ''}',
        email: '${j['email'] ?? ''}',
        refresh: '${j['refresh']}',
      );
}

/// Las otras cuentas abiertas en este celular (almacenamiento cifrado, como la sesión)
class CuentasGuardadas {
  static const String _clave = 'cuentas_guardadas';

  static Future<List<CuentaGuardada>> todas() async {
    try {
      final texto = await SessionStore.almacen.leer(_clave);
      if (texto == null || texto.isEmpty) return [];
      return [for (final c in jsonDecode(texto) as List) CuentaGuardada.desdeJson(Map<String, dynamic>.from(c as Map))];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _escribir(List<CuentaGuardada> lista) =>
      lista.isEmpty ? SessionStore.almacen.borrar(_clave) : SessionStore.almacen.escribir(_clave, jsonEncode([for (final c in lista) c.aJson()]));

  static Future<CuentaGuardada?> de(String usuario) async => (await todas()).where((c) => c.usuario == usuario).firstOrNull;

  static Future<void> guardar(CuentaGuardada cuenta) async => _escribir([cuenta, ...(await todas()).where((c) => c.usuario != cuenta.usuario)]);

  static Future<void> quitar(String usuario) async => _escribir((await todas()).where((c) => c.usuario != usuario).toList());
}
