import 'dart:convert';
import 'api_http.dart' as http;
import '../config/constants.dart';

class PasswordResetService {
  // Usar la misma URL que el resto de la app
  static String get baseUrl => AppConstants.baseUrl;

  static Future<void> forgotPassword(String email) async {
    final uri = Uri.parse('$baseUrl/auth/forgot-password');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Error solicitando código');
    }
  }

  /// Con varias cuentas con el mismo correo devuelve todas (cada una con su resetToken) para elegir cuál recuperar
  static Future<List<({String usuario, String tipoUsuario, String estado, String resetToken})>> verifyCode(String email, String code) async {
    final uri = Uri.parse('$baseUrl/auth/verify-reset-code');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Código inválido');
    }
    if (data['cuentas'] is List) {
      return [
        for (final c in data['cuentas'] as List)
          (usuario: '${c['usuario']}', tipoUsuario: '${c['tipoUsuario']}', estado: '${c['estado'] ?? 'activo'}', resetToken: '${c['resetToken']}'),
      ];
    }
    return [(usuario: '${data['usuario'] ?? ''}', tipoUsuario: '${data['tipoUsuario'] ?? ''}', estado: 'activo', resetToken: '${data['resetToken'] ?? ''}')];
  }

  /// Devuelve el usuario al que se le cambió la contraseña
  static Future<String> resetPassword(
    String resetToken,
    String newPassword,
  ) async {
    final uri = Uri.parse('$baseUrl/auth/reset-password');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'resetToken': resetToken, 'newPassword': newPassword}),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Error reseteando contraseña');
    }
    return (data['message'] ?? 'Contraseña actualizada').toString();
  }
}
