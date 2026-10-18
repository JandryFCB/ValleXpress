import 'dart:convert';
import 'api_http.dart' as http;
import '../config/constants.dart';
import 'api_error.dart';
import 'dispositivo.dart';
import 'session_store.dart';

/// Por qué no se pudo entrar, con lo que la pantalla de login necesita para explicarlo bien:
/// cuenta bloqueada por intentos (con los segundos que faltan), bloqueada o dada de baja por el administrador,
/// o cuántos intentos quedan antes del bloqueo.
class ErrorLogin implements Exception {
  const ErrorLogin(this.mensaje, {this.codigo, this.segundos, this.intentosRestantes, this.estatus, this.soporte, this.cuentas = const []});

  final String mensaje;
  final String? codigo;

  /// Segundos que faltan para que se desbloquee (CUENTABLOQUEADA)
  final int? segundos;
  final int? intentosRestantes;

  /// 'bloqueado' | 'inactivo' cuando el administrador la desactivó (CUENTADESACTIVADA)
  final String? estatus;

  /// Correo de soporte para escribir
  final String? soporte;

  /// Varias cuentas (una por perfil) con el mismo correo y la misma clave: [{usuario, tipoUsuario}] para elegir
  final List<Map<String, String>> cuentas;

  bool get elegirCuenta => codigo == 'ELEGIRCUENTA' && cuentas.isNotEmpty;
  bool get bloqueoTemporal => codigo == 'CUENTABLOQUEADA';
  bool get desactivada => codigo == 'CUENTADESACTIVADA';

  @override
  String toString() => mensaje;
}

class AuthService {
  // Login
  // tipoUsuario: con qué cuenta entrar cuando la persona tiene varias con el mismo correo (ELEGIRCUENTA)
  Future<Map<String, dynamic>> login(String email, String password, {String? tipoUsuario}) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password, if (tipoUsuario != null) 'tipoUsuario': tipoUsuario, ...await datosDispositivo()}),
      );
    } catch (e) {
      throw const ErrorLogin('No pudimos conectarnos. Revisa tu internet e intenta de nuevo', codigo: 'SINCONEXION');
    }
    if (response.statusCode == 200) return json.decode(response.body);

    Map<String, dynamic> e = {};
    try {
      e = Map<String, dynamic>.from(json.decode(response.body));
    } catch (_) {
      // respuesta sin JSON
    }
    throw ErrorLogin(
      '${e['error'] ?? 'No se pudo iniciar sesión (${response.statusCode})'}',
      codigo: e['code']?.toString(),
      segundos: (e['retryAfter'] as num?)?.toInt(),
      intentosRestantes: (e['intentosRestantes'] as num?)?.toInt(),
      estatus: e['estatus']?.toString(),
      soporte: e['soporte']?.toString(),
      cuentas: [
        for (final c in (e['cuentas'] as List? ?? const []))
          if (c is Map) {'usuario': '${c['usuario']}', 'tipoUsuario': '${c['tipoUsuario']}'},
      ],
    );
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
        'aceptaTerminos': true, // la pantalla no deja registrarse sin marcar "Acepto"; el servidor guarda la versión
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

  // Cierra la sesión de este equipo en el servidor (el refresh token deja de servir). Si no hay internet, igual se
  // cierra la sesión local. Solo lanza error si el servidor se niega: el repartidor con una entrega en curso (409).
  Future<void> logout(String? refreshToken) async {
    if (refreshToken == null) return;
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return; // sin red: la sesión local se cierra igual
    }
    if (res.statusCode == 409) throw Exception(mensajeDeError(res, 'Termina tu entrega antes de cerrar sesión'));
  }

  /// Abre la sesión de una cuenta guardada en el celular canjeando su refresh token. null = esa sesión ya no sirve
  /// (venció, cambió la clave...) y hay que escribir la contraseña. Sin internet lanza error.
  Future<Map<String, dynamic>?> sesionGuardada(String refreshToken) async {
    final res = await http
        .post(Uri.parse('${AppConstants.baseUrl}/auth/refresh'), headers: {'Content-Type': 'application/json'}, body: json.encode({'refreshToken': refreshToken}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) return Map<String, dynamic>.from(json.decode(res.body) as Map);
    if (res.statusCode == 401 || res.statusCode == 403) return null;
    throw Exception(mensajeDeError(res, 'No pudimos abrir esa cuenta. Intenta de nuevo'));
  }

  /// Las cuentas de la persona (cliente, vendedor, repartidor) para cambiar entre ellas: [{usuario, tipoUsuario, actual}]
  Future<List<Map<String, dynamic>>> misCuentas() async {
    final token = await SessionStore.accessToken();
    if (token == null) return [];
    final res = await http.get(Uri.parse('${AppConstants.baseUrl}/auth/cuentas'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudieron cargar tus cuentas'));
    return [for (final c in (json.decode(res.body)['cuentas'] as List)) Map<String, dynamic>.from(c as Map)];
  }

  // Cierra la sesión en TODOS los equipos del usuario (incluido este). Necesita el token de acceso.
  Future<void> cerrarTodas() async {
    final token = await SessionStore.accessToken();
    if (token == null) throw Exception('Tu sesión no está activa');
    final res = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/logout-all'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    );
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudieron cerrar las sesiones'));
  }

  /// Elimina la cuenta (con la contraseña): el servidor borra los datos personales y cierra todas las sesiones
  Future<void> eliminarCuenta(String password) async {
    final token = await SessionStore.accessToken();
    if (token == null) throw Exception('Tu sesión no está activa');
    final res = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/eliminar-cuenta'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: json.encode({'password': password}),
    );
    if (res.statusCode != 200) throw Exception(mensajeDeError(res, 'No se pudo eliminar la cuenta'));
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
    String? tipoUsuario,
  }) async {
    try {
      final body = {'email': email, 'nombre': nombre, if (tipoUsuario != null) 'tipoUsuario': tipoUsuario};

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

  /// Perfiles con el registro abierto ({cliente: true, vendedor: true, repartidor: false}). El administrador puede
  /// cerrar uno desde "Perfiles y permisos". Sin conexión devuelve null (el servidor vuelve a validar al registrar).
  Future<Map<String, bool>?> perfilesRegistro() async {
    try {
      final res = await http.get(Uri.parse('${AppConstants.baseUrl}/auth/registro/perfiles'), headers: {'Content-Type': 'application/json'});
      if (res.statusCode != 200) return null;
      final perfiles = Map<String, dynamic>.from(json.decode(res.body)['perfiles'] as Map);
      return perfiles.map((rol, abierto) => MapEntry(rol, abierto == true));
    } catch (_) {
      return null;
    }
  }

  // ✅ Verificar si cédula ya existe (validación en tiempo real)
  // tipo: el perfil que está creando (una persona puede tener una cuenta de cada perfil)
  Future<Map<String, dynamic>> checkCedula(String cedula, {String? tipo}) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/check-cedula/$cedula${tipo != null ? '?tipo=$tipo' : ''}'),
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
  Future<Map<String, dynamic>> checkEmail(String email, {String? tipo}) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/check-email/$email${tipo != null ? '?tipo=$tipo' : ''}'),
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
