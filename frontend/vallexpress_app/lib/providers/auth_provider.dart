import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../config/navegacion.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../services/session_store.dart';
import '../services/socket_tracking_service.dart';
import '../services/fcm_mobile.dart'
    if (dart.library.html) 'fcm_stub_import.dart';

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

      var acceso = await SessionStore.accessToken();
      if (!SessionStore.accesoVigente(acceso)) {
        // Venció (la app estuvo cerrada): se renueva ahora. Si no hay internet, la sesión se conserva y se
        // renovará con la primera petición.
        await SessionManager.instance.refrescar();
        acceso = await SessionStore.accessToken();
      }
      _token = acceso; // null si el servidor cerró la sesión

      if (_token != null) {
        FcmService.registrarDispositivo();
      } else {
        _usuario = null;
      }
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
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _iniciarSesion(await _authService.login(email, password));
      FcmService.registrarDispositivo();
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usuario', jsonEncode(_usuario));
  }

  // ---------------------------------------------------------------------------------------------
  // Cerrar sesión
  // ---------------------------------------------------------------------------------------------
  Future<void> logout() async {
    TrackingSocketService().reset(); // limpiar el socket antes de cerrar sesión
    if (_token != null) await FcmService.quitarDispositivo(_token!);

    // Se avisa al servidor para que este refresh token deje de servir, y se borra todo lo local
    await _authService.logout(await SessionStore.refreshToken());
    await _limpiarLocal();
    notifyListeners();
  }

  Future<void> _limpiarLocal() async {
    await SessionStore.limpiar();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('usuario');
    _token = null;
    _usuario = null;
  }

  // El servidor cerró la sesión (venció, la cerraron desde otro equipo, cuenta desactivada...)
  Future<void> _alTerminarSesion(String codigo) async {
    TrackingSocketService().reset();
    await _limpiarLocal();
    notifyListeners();

    final contexto = navigatorKey.currentContext;
    if (contexto != null) {
      ScaffoldMessenger.maybeOf(contexto)?.showSnackBar(SnackBar(content: Text(SessionManager.mensajeDe(codigo))));
    }
    navigatorKey.currentState?.pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
  }

  String _limpiar(Object e) => e.toString().replaceFirst('Exception: ', '');

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
