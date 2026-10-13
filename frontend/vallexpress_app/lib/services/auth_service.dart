import 'dart:convert';
import 'api_http.dart' as http;
import '../config/constants.dart';
import 'dispositivo.dart';

class AuthService {
  // Login
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password, ...await datosDispositivo()}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al iniciar sesión');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // Registro
  Future<Map<String, dynamic>> register({
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
    try {
      final body = {
        'nombre': nombre,
        'apellido': apellido,
        'email': email,
        'telefono': telefono,
        'cedula': cedula,
        'password': password,
        'tipoUsuario': tipoUsuario,
        ...await datosDispositivo(),
      };

      // Agregar campos opcionales según el tipo de usuario
      if (tipoUsuario == 'vendedor' && nombreNegocio != null) {
        body['nombreNegocio'] = nombreNegocio;
      }
      if (tipoUsuario == 'repartidor') {
        if (vehiculo != null) body['vehiculo'] = vehiculo;
        if (placa != null) body['placa'] = placa;
      }

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al registrar usuario');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // Cierra la sesión de este equipo en el servidor (el refresh token deja de servir). Nunca lanza error:
  // si no hay internet, igual se cierra la sesión local.
  Future<void> logout(String? refreshToken) async {
    if (refreshToken == null) return;
    try {
      await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // sin red: la sesión local se cierra igual
    }
  }

  // Solicitar código de recuperación de contraseña
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al solicitar código');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // Verificar código de recuperación
  Future<Map<String, dynamic>> verifyResetCode(
    String email,
    String code,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/verify-reset-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Código inválido');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // Restablecer contraseña
  Future<Map<String, dynamic>> resetPassword(
    String resetToken,
    String newPassword,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'resetToken': resetToken,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al restablecer contraseña');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // 📧 Enviar código de verificación de email
  Future<Map<String, dynamic>> sendEmailVerification(
    String email,
    String nombre, {
    String? fcmToken,
  }) async {
    try {
      final body = {'email': email, 'nombre': nombre};

      // Agregar FCM token si está disponible
      if (fcmToken != null && fcmToken.isNotEmpty) {
        body['fcmToken'] = fcmToken;
      }

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/send-verification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al enviar código');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ✅ Verificar código de email
  Future<Map<String, dynamic>> verifyEmailCode(
    String email,
    String code,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Código inválido');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ✅ Verificar si cédula ya existe (validación en tiempo real)
  Future<Map<String, dynamic>> checkCedula(String cedula) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/check-cedula/$cedula'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al verificar cédula');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ✅ Verificar si email ya existe (validación en tiempo real)
  Future<Map<String, dynamic>> checkEmail(String email) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/check-email/$email'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al verificar email');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ✅ Verificar si placa ya existe (validación en tiempo real)
  Future<Map<String, dynamic>> checkPlaca(String placa) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/check-placa/$placa'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Error al verificar placa');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }
}
