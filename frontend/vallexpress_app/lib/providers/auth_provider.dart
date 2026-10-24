import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../config/navegacion.dart';
import '../services/auth_service.dart';
import '../services/api_error.dart';
import '../services/session_manager.dart';
import '../services/session_store.dart';
import '../services/tiempo_real.dart';
import 'carrito_provider.dart';
import '../services/gps_repartidor.dart';
import '../models/pedido.dart';
import '../services/pedidos_service.dart';
import '../services/fcm_mobile.dart'
    if (dart.library.html) '../services/fcm_web.dart';

/// Estado de la sesión del usuario. Sesión persistente: al abrir la app se restaura sola con el refresh token
/// guardado (cifrado), así que el usuario solo escribe su clave la primera vez o cuando la cierra él mismo.
class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _restaurando = true; // true mientras se revisa si hay una sesión guardada (pantalla de inicio)
  String? _error;
  String? _token;
  Map<String, dynamic>? _usuario;
  StreamSubscription<String>? _subRenovado;
  StreamSubscription<String>? _subTerminada;

  bool get isLoading => _isLoading;
  bool get isRestoring => _restaurando;
  String? get error => _error;
  bool get isAuthenticated => _token != null;
  Map<String, dynamic>? get usuario => _usuario;
  String? get token => _token;

  AuthProvider() {
    // Cuando el token se renueva solo, el provider se entera (los sockets y pantallas leen de aquí)
    _subRenovado = SessionManager.instance.renovado.listen((nuevo) {
      _token = nuevo;
      notifyListeners();
    });
    // Cuando el servidor dice que la sesión ya no sirve, se vuelve al login con un aviso
    _subTerminada = SessionManager.instance.sesionTerminada.listen(_alTerminarSesion);
    restaurarSesion();
  }

  @override
  void dispose() {
    _subRenovado?.cancel();
    _subTerminada?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------------------------
  // Restaurar la sesión al abrir la app
  // ---------------------------------------------------------------------------------------------
  Future<void> restaurarSesion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token'); // token viejo de 30 días de versiones anteriores: ya no se usa

      final refresh = await SessionStore.refreshToken();
      if (refresh == null) return; // nunca inició sesión (o la cerró)

      final guardado = prefs.getString('usuario');
      if (guardado != null) _usuario = jsonDecode(guardado) as Map<String, dynamic>;

      // Se entra enseguida con lo guardado. Si el token de acceso venció (la app estuvo cerrada) se renueva en
      // segundo plano: antes se esperaba aquí y, sin internet, la pantalla de inicio se quedaba hasta 15 s.
      // Si el servidor dice que la sesión terminó, SessionManager avisa y se vuelve al login.
      var acceso = await SessionStore.accessToken();
      // Caso raro (sin token de acceso guardado): ahí sí hay que esperar la renovación
      if (acceso == null) {
        await SessionManager.instance.refrescar();
        acceso = await SessionStore.accessToken();
      } else if (!SessionStore.accesoVigente(acceso)) {
        SessionManager.instance.refrescar().catchError((_) => false); // el token nuevo llega por "renovado"
      }
      _token = _usuario == null ? null : acceso;
      if (_token != null) FcmService.registrarDispositivo();
    } catch (e) {
      debugPrint('No se pudo restaurar la sesión: $e');
    } finally {
      _restaurando = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Login y registro
  // ---------------------------------------------------------------------------------------------
  /// Detalle del último login fallido (bloqueo, intentos que quedan...) para que la pantalla lo explique
  ErrorLogin? errorLogin;

  Future<bool> login(String email, String password, {String? tipoUsuario}) async {
    _isLoading = true;
    _error = null;
    errorLogin = null;
    notifyListeners();

    try {
      await _iniciarSesion(await _authService.login(email, password, tipoUsuario: tipoUsuario));
      FcmService.registrarDispositivo();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (e is ErrorLogin) errorLogin = e;
      _error = _limpiar(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String nombre,
    required String apellido,
    required String email,
    required String telefono,
    required String cedula,
    required String password,
    required String tipoUsuario,
    String? nombreNegocio,
    String? vehiculo,
    String? placa,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _iniciarSesion(await _authService.register(
        nombre: nombre,
        apellido: apellido,
        email: email,
        telefono: telefono,
        cedula: cedula,
        password: password,
        tipoUsuario: tipoUsuario,
        nombreNegocio: nombreNegocio,
        vehiculo: vehiculo,
        placa: placa,
      ));
      FcmService.registrarDispositivo(); // igual que en el login: las notificaciones push empiezan desde el registro
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _limpiar(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Guarda la sesión que entregó el servidor: tokens en almacenamiento cifrado, datos del usuario en preferencias
  Future<void> _iniciarSesion(Map<String, dynamic> respuesta) async {
    final acceso = respuesta['token'] as String;
    final refresh = respuesta['refreshToken'] as String?;
    if (refresh == null) throw Exception('El servidor no entregó una sesión persistente');

    await SessionManager.instance.guardarSesion(acceso: acceso, refresh: refresh);
    _token = acceso;
    _usuario = respuesta['usuario'] as Map<String, dynamic>?;
    // Si estaba entre las cuentas guardadas, ahora es la que se usa
    if (_usuario?['id'] != null) await CuentasGuardadas.quitar('${_usuario!['id']}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usuario', jsonEncode(_usuario));
  }

  // ---------------------------------------------------------------------------------------------
  // Cerrar sesión
  // ---------------------------------------------------------------------------------------------
  // ---------------------------------------------------------------------------------------------
  // Varias cuentas en el celular (una persona: cliente, negocio y repartidor)
  // ---------------------------------------------------------------------------------------------
  /// Las otras cuentas con sesión abierta en este celular
  Future<List<CuentaGuardada>> cuentasGuardadas() => CuentasGuardadas.todas();

  /// Las cuentas de la persona según el servidor ([{usuario, tipoUsuario, actual}])
  Future<List<Map<String, dynamic>>> misCuentas() => _authService.misCuentas();

  // El repartidor no deja la cuenta (cerrar sesión o cambiar) con una entrega aceptada o recogida
  Future<void> _exigirSinEntregaEnCurso() async {
    if (_usuario?['tipoUsuario'] != 'repartidor') return;
    final activos = await PedidosService.misEntregas(estado: 'activos').then((r) => r.pedidos).catchError((_) => <Pedido>[]);
    final enCurso = activos.where((p) => p.enReparto).firstOrNull;
    if (enCurso != null) throw Exception('Tienes la entrega del pedido #${enCurso.id} en curso. Termínala antes de salir de esta cuenta');
  }

  /// Cambia a otra cuenta de la persona sin cerrar la actual (queda guardada para volver). Si la otra cuenta ya
  /// tiene sesión en el celular entra directo; si no, hace falta su contraseña ([clave]): devuelve false si falta.
  Future<bool> cambiarACuenta(String usuario, {String? clave, String? tipoUsuario}) async {
    if (usuario == _usuario?['id']) return true;
    await _exigirSinEntregaEnCurso();

    // 1) Se consigue la sesión de la otra cuenta ANTES de tocar la actual (si falla, todo sigue igual)
    Map<String, dynamic>? respuesta;
    final guardada = await CuentasGuardadas.de(usuario);
    if (guardada != null) {
      respuesta = await _authService.sesionGuardada(guardada.refresh);
      if (respuesta == null) await CuentasGuardadas.quitar(usuario); // esa sesión ya no sirve: pide la contraseña
    }
    if (respuesta == null) {
      if (clave == null) return false;
      respuesta = await _authService.login(usuario, clave, tipoUsuario: tipoUsuario);
    }

    // 2) La cuenta actual queda guardada (el repartidor sale de línea: ya no llevará el GPS)
    if (_usuario?['tipoUsuario'] == 'repartidor') await PedidosService.cambiarDisponibilidad(false).then((_) {}).catchError((_) {});
    final refreshActual = await SessionStore.refreshToken();
    if (_usuario != null && refreshActual != null) {
      await CuentasGuardadas.guardar(CuentaGuardada(
        usuario: '${_usuario!['id']}',
        tipoUsuario: '${_usuario!['tipoUsuario'] ?? 'cliente'}',
        nombre: '${_usuario!['nombre'] ?? ''}',
        email: '${_usuario!['email'] ?? ''}',
        refresh: refreshActual,
      ));
    }

    // 3) Se entra a la otra: lo de la cuenta anterior (avisos en vivo, GPS, carrito) no pasa a esta
    _detenerLoDeLaCuenta();
    await _iniciarSesion(respuesta);
    FcmService.registrarDispositivo();
    notifyListeners();
    return true;
  }

  /// Desde el login: entra a una cuenta que quedó abierta en el celular. false = hay que escribir la contraseña.
  Future<bool> entrarConGuardada(String usuario) async {
    final guardada = await CuentasGuardadas.de(usuario);
    if (guardada == null) return false;
    final respuesta = await _authService.sesionGuardada(guardada.refresh);
    if (respuesta == null) {
      await CuentasGuardadas.quitar(usuario);
      return false;
    }
    await _iniciarSesion(respuesta);
    FcmService.registrarDispositivo();
    notifyListeners();
    return true;
  }

  /// Quita una cuenta guardada del celular: cierra su sesión en el servidor y deja de recibir sus avisos
  Future<void> olvidarCuenta(String usuario) async {
    final guardada = await CuentasGuardadas.de(usuario);
    await CuentasGuardadas.quitar(usuario);
    if (guardada == null) return;
    try {
      final r = await _authService.sesionGuardada(guardada.refresh);
      if (r == null) return;
      await FcmService.quitarDispositivo(r['token'] as String);
      await _authService.logout(r['refreshToken'] as String?);
    } catch (_) {
      // sin internet: la sesión vence sola en el servidor
    }
    notifyListeners();
  }

  /// Cierra la sesión. El repartidor con una entrega en curso (aceptada o recogida) NO puede: lanza el motivo para
  /// mostrarlo (el cliente y el negocio lo están esperando). El servidor también lo verifica.
  Future<void> logout() async {
    await _exigirSinEntregaEnCurso();
    // Se avisa al servidor para que este refresh token deje de servir (y al repartidor lo saca de línea)
    await _authService.logout(await SessionStore.refreshToken());
    if (_token != null) await FcmService.quitarDispositivo(_token!);
    await _limpiarLocal();
    notifyListeners();
  }

  /// Cierra la sesión en todos los dispositivos del usuario (por ejemplo si perdió el celular) y también en este.
  Future<void> cerrarSesionEnTodos() async {
    await _authService.cerrarTodas();     // el servidor se niega si el repartidor tiene una entrega en curso
    await logout();
  }

  /// Elimina la cuenta: el servidor cierra todas las sesiones y saca de línea al repartidor; aquí se borra lo local
  Future<void> eliminarCuenta(String password) async {
    await _authService.eliminarCuenta(password);
    await _limpiarLocal();
    notifyListeners();
  }

  // Lo de esta cuenta no debe pasar a la siguiente: avisos en vivo, GPS del repartidor y carrito
  void _detenerLoDeLaCuenta() {
    TiempoReal.instancia.detener();
    GpsRepartidor.instancia.detener();
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) Provider.of<CarritoProvider>(ctx, listen: false).vaciar();
  }

  Future<void> _limpiarLocal() async {
    _detenerLoDeLaCuenta();
    await SessionStore.limpiar();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('usuario');
    _token = null;
    _usuario = null;
  }

  // El servidor cerró la sesión (venció, la cerraron desde otro equipo, cuenta desactivada...)
  Future<void> _alTerminarSesion(String codigo) async {
    await _limpiarLocal();
    notifyListeners();

    final contexto = navigatorKey.currentContext;
    if (contexto != null && contexto.mounted) {
      ScaffoldMessenger.maybeOf(contexto)?.showSnackBar(SnackBar(content: Text(SessionManager.mensajeDe(codigo))));
    }
    navigatorKey.currentState?.pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
  }

  /// Actualiza los datos del usuario que la app tiene guardados (por ejemplo tras editar su nombre en el perfil),
  /// para que el saludo del inicio y demás pantallas los muestren al instante.
  Future<void> actualizarUsuario(Map<String, dynamic> cambios) async {
    _usuario = {...?_usuario, ...cambios};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usuario', jsonEncode(_usuario));
  }

  String _limpiar(Object e) => textoDeError(e);

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
