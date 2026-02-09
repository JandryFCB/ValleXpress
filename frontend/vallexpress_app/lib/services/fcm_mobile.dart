import 'package:firebase_core/firebase_core.dart';
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
  static Future<void> registerDeviceToken(String token, String platform) async {
    // Implementa aquí el registro del token en tu backend si lo necesitas
    // Ejemplo: await http.post('https://tu-backend.com/api/register-token', body: {...});
  }
}

class FcmService {
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

    final fcmToken = await fm.getToken();

    if (fcmToken != null) {
      debugPrint('FCM token: $fcmToken');
      try {
        await NotificationService.registerDeviceToken(fcmToken, 'android');
      } catch (e) {
        debugPrint('Error registrando el token del dispositivo: $e');
      }
    } else {
      debugPrint('No se recibió el token FCM');
    }

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
