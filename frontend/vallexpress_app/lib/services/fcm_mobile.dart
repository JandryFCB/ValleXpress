import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'api_http.dart' as http;
import 'session_store.dart';
import '../config/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar, Text;
import 'api_error.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import '../config/navegacion.dart';
import '../providers/auth_provider.dart';
import '../utils/abrir_pedido.dart';

/// Canales de notificación de Android (deben coincidir con canalDe() de backend/src/services/fcm.service.js).
/// Se crean al abrir la app; Android los usa también para las push que llegan con la app cerrada.
const _canalPedidos = AndroidNotificationChannel(
  'pedidos',
  'Pedidos y entregas',
  description:
      'Pedidos nuevos, cambios de estado y tu repartidor: suenan y aparecen arriba de la pantalla',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);
const _canalGeneral = AndroidNotificationChannel(
  'general',
  'Avisos de tu cuenta',
  description: 'Aprobaciones, seguridad y otros avisos',
  importance: Importance.high,
  playSound: true,
);

bool _esDePedido(String? tipo) => RegExp(
  r'^(pedido|repartidor_cerca|repartidor_asignado)',
).hasMatch(tipo ?? '');

/// Abre el pedido (o la pantalla de cuentas) de una notificación tocada, cuando la app ya tiene a dónde navegar
void _abrirDesdeNotificacion(Map<String, dynamic> data) {
  final id = int.tryParse('${data['pedidoId'] ?? ''}');
  final tipo = data['tipo']?.toString();
  if (id == null && !const {'comprobante_nuevo', 'suscripcion_pagada', 'comprobante_rechazado', 'advertencia_repartidor', 'sugerencia_nueva', 'sugerencia_respondida', 'documentos_recordatorio'}.contains(tipo)) return;
  final cuenta = data['cuenta']?.toString();
  Future<void> intentar(int vez) async {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.read<AuthProvider>().isAuthenticated) {
      final auth = ctx.read<AuthProvider>();
      // El aviso es de otra cuenta de la persona (negocio, repartidor...): se cambia a ella antes de abrirlo
      if (cuenta != null && cuenta != auth.usuario?['id']?.toString()) {
        try {
          if (!await auth.cambiarACuenta(cuenta)) return;
        } catch (e) {
          final c = navigatorKey.currentContext;
          if (c != null && c.mounted) ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(textoDeError(e))));
          return;
        }
        navigatorKey.currentState?.pushNamedAndRemoveUntil(AppConstants.homeRoute, (_) => false);
        await Future.delayed(const Duration(milliseconds: 400));
        final c = navigatorKey.currentContext;
        if (c != null && c.mounted) abrirAviso(c, tipo: tipo, pedidoId: id);
        return;
      }
      abrirAviso(ctx, tipo: tipo, pedidoId: id);
    } else if (vez < 20) {
      // Al abrir la app desde cero, la sesión tarda un instante en restaurarse
      Future.delayed(
        const Duration(milliseconds: 300),
        () => intentar(vez + 1),
      );
    }
  }

  intentar(0);
}

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static int _siguienteId =
      DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000;

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_notificacion');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == null) return;
        try {
          _abrirDesdeNotificacion(
            Map<String, dynamic>.from(jsonDecode(r.payload!) as Map),
          );
        } catch (_) {}
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_canalPedidos);
    await android?.createNotificationChannel(_canalGeneral);
  }

  /// Muestra una notificación con la app abierta. Cada una con su número: no se pisan entre sí.
  static Future<void> showNotification({
    String? title,
    String? body,
    Map<String, dynamic>? data,
  }) async {
    final canal = _esDePedido(data?['tipo']?.toString())
        ? _canalPedidos
        : _canalGeneral;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        canal.id,
        canal.name,
        channelDescription: canal.description,
        importance: canal.importance,
        priority: Priority.max,
        playSound: true,
      ),
    );
    await _plugin.show(
      _siguienteId++,
      title ?? 'ValleXpress',
      body ?? '',
      details,
      payload: data == null ? null : jsonEncode(data),
    );
  }
}

class NotificationService {
  static String? _ultimoToken;

  /// Registra el token FCM en el backend (POST /notificaciones/dispositivo).
  /// Necesita sesión iniciada: si no hay JWT guardado no hace nada.
  static Future<void> registerDeviceToken(String token, String platform) async {
    final jwt = await SessionStore.accessToken();
    if (jwt == null) return;
    final res = await http.post(
      Uri.parse('${AppConstants.baseUrl}/notificaciones/dispositivo'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({'token': token, 'plataforma': platform}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _ultimoToken = token;
    } else {
      debugPrint(
        'No se registró el dispositivo: ${res.statusCode} ${res.body}',
      );
    }
  }

  /// Quita el token de este dispositivo (al cerrar sesión) para no recibir pushes de otro usuario.
  static Future<void> unregisterDeviceToken(String jwt) async {
    final token = _ultimoToken;
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('${AppConstants.baseUrl}/notificaciones/dispositivo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
    _ultimoToken = null;
  }
}

class FcmService {
  // Solo en la web (fcm_web.dart): el aviso "Activa las notificaciones". En el celular el permiso se pide al abrir.
  static bool get permisoPendiente => false;
  static void descartar() {}
  static Future<bool> activar() async => false;

  static String get _plataforma => Platform.isIOS ? 'ios' : 'android';

  static Future<void> _registrar(String token) async {
    try {
      await NotificationService.registerDeviceToken(token, _plataforma);
    } catch (e) {
      debugPrint('Error registrando el token del dispositivo: $e');
    }
  }

  static int _intento = 0;

  /// Obtiene el token FCM y lo registra. Se llama al abrir la app y después de iniciar sesión.
  /// Google Play a veces responde "SERVICE_NOT_AVAILABLE" (mala señal, recién instalada): se reintenta con
  /// esperas crecientes (2, 4, 8, 16, 32 s) en vez de dejar al usuario sin notificaciones hasta reabrir la app.
  static Future<void> registrarDispositivo() async {
    if (kIsWeb) return;
    final intento =
        ++_intento; // un login nuevo reinicia los reintentos del anterior
    for (var vez = 0; vez < 6 && intento == _intento; vez++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) await _registrar(token);
        return;
      } catch (e) {
        debugPrint('Sin token FCM (intento ${vez + 1}): $e');
        await Future.delayed(Duration(seconds: 2 << vez));
      }
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

    // Tocar una push con la app en segundo plano o cerrada abre ese pedido
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _abrirDesdeNotificacion(m.data),
    );
    final inicial = await fm.getInitialMessage();
    if (inicial != null) _abrirDesdeNotificacion(inicial.data);
  }
}
