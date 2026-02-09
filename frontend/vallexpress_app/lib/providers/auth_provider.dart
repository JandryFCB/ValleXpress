import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/socket_tracking_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  String? _error;
  String? _token;
  Map<String, dynamic>? _usuario;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null;
  Map<String, dynamic>? get usuario => _usuario;
  String? get token => _token;

  AuthProvider() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');

    // Cargar usuario también si existe token
    if (_token != null) {
      final userJson = prefs.getString('usuario');
      if (userJson != null) {
        _usuario = jsonDecode(userJson) as Map<String, dynamic>;
      }
    }

    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.login(email, password);

      _token = response['token'];
      _usuario = response['usuario'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('usuario', jsonEncode(_usuario));

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
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
      final response = await _authService.register(
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
      );

      _token = response['token'];
      _usuario = response['usuario'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('usuario', jsonEncode(_usuario));

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    // Limpiar socket antes de cerrar sesión
    TrackingSocketService().reset();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario');

    _token = null;
    _usuario = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
