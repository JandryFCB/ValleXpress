import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );
    await _plugin.initialize(settings);
  }

  static Future<void> showNotification({
    String? title,
    String? body,
    Map<String, dynamic>? data,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'channel_id',
          'channel_name',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await _plugin.show(
      0,
      title ?? 'Notificación',
      body ?? '',
      details,
      payload: data?.toString(),
    );
  }
}

class NotificationService {
  static String? _ultimoToken;

  /// Registra el token FCM en el backend (POST /notificaciones/dispositivo).
  /// Necesita sesión iniciada: si no hay JWT guardado no hace nada.
  static Future<void> registerDeviceToken(String token, String platform) async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString(AppConstants.tokenKey);
    if (jwt == null) return;
    final res = await http.post(
      Uri.parse('${AppConstants.baseUrl}/notificaciones/dispositivo'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $jwt'},
      body: jsonEncode({'token': token, 'plataforma': platform}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _ultimoToken = token;
    } else {
      debugPrint('No se registró el dispositivo: ${res.statusCode} ${res.body}');
    }
  }

  /// Quita el token de este dispositivo (al cerrar sesión) para no recibir pushes de otro usuario.
  static Future<void> unregisterDeviceToken(String jwt) async {
    final token = _ultimoToken;
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('${AppConstants.baseUrl}/notificaciones/dispositivo'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $jwt'},
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
    _ultimoToken = null;
  }
}

class FcmService {
  static String get _plataforma => Platform.isIOS ? 'ios' : 'android';

  static Future<void> _registrar(String token) async {
    try {
      await NotificationService.registerDeviceToken(token, _plataforma);
    } catch (e) {
      debugPrint('Error registrando el token del dispositivo: $e');
    }
  }

  /// Obtiene el token FCM y lo registra. Se llama al abrir la app y después de iniciar sesión.
  static Future<void> registrarDispositivo() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registrar(token);
    } catch (e) {
      debugPrint('Sin token FCM: $e');
    }
  }

  static Future<void> quitarDispositivo(String jwt) =>
      NotificationService.unregisterDeviceToken(jwt);

  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Error al inicializar Firebase: $e');
    }

    // Inicializar notificaciones locales
    await LocalNotificationService.initialize();

    final fm = FirebaseMessaging.instance;
    // Solicitar permisos de notificación (Android 13 / iOS)
    try {
      await fm.requestPermission();
    } catch (e) {
      debugPrint('Error al solicitar permisos: $e');
    }

    await registrarDispositivo();
    // Si Firebase renueva el token, se vuelve a registrar
    fm.onTokenRefresh.listen((t) => _registrar(t));

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title =
          message.notification?.title ?? message.data['title']?.toString();
      final body =
          message.notification?.body ?? message.data['body']?.toString();
      LocalNotificationService.showNotification(
        title: title,
        body: body,
        data: message.data,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Abierto desde la notificación: ${message.data}');
    });
  }
}
