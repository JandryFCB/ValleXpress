import 'dart:convert';
import 'package:http/http.dart' as http;
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

  static Future<String> verifyCode(String email, String code) async {
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
    return (data['resetToken'] ?? '').toString();
  }

  static Future<void> resetPassword(
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
  }
}
