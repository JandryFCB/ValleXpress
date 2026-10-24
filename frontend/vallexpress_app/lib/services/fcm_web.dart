// Notificaciones push en la web (Firebase Cloud Messaging en el navegador). Reemplaza a fcm_mobile.dart al compilar
// para la web. Con la pestaña abierta los avisos ya llegan en vivo (socket); esto es para cuando está cerrada.
// Los navegadores (sobre todo el iPhone) solo dejan pedir el permiso al tocar un botón: por eso [activar] se llama
// desde el aviso "Activa las notificaciones" y [registrarDispositivo] solo registra si el permiso ya estaba dado.
import 'dart:convert';
import 'dart:js_interop_unsafe';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../config/constants.dart';
import '../config/firebase_web.dart';
import '../config/navegacion.dart';
import '../providers/auth_provider.dart';
import '../utils/abrir_pedido.dart';
import '../web/escritorio.dart';
import 'api_http.dart' as http;
import 'session_store.dart';

const _claveDescartado = 'vx_aviso_notificaciones_descartado';

class FcmService {
  static bool _listo = false;
  static String? _ultimoToken;

  /// El navegador puede mostrar notificaciones (en el iPhone, solo con la web agregada a la pantalla de inicio)
  static bool get _soportado => web.window.has('Notification') && web.window.navigator.has('serviceWorker');

  static String get _permiso => _soportado ? web.Notification.permission : 'denied';

  /// Mostrar el aviso para activarlas: se pueden pedir, aún no se pidieron y la persona no lo cerró
  static bool get permisoPendiente {
    if (!_listo || _permiso != 'default') return false;
    try {
      return web.window.localStorage.getItem(_claveDescartado) == null;
    } catch (_) {
      return true;
    }
  }

  /// "Ahora no": el aviso no vuelve a salir en este navegador
  static void descartar() {
    try {
      web.window.localStorage.setItem(_claveDescartado, '1');
    } catch (_) {}
  }

  static Future<void> initialize() async {
    // Se abrió desde una notificación tocada (el backend manda ?aviso=tipo&pedido=id). Se lee antes de esperar a
    // Firebase: la app cambia la dirección de la página al mostrar la primera pantalla
    final q = Uri.base.queryParameters;
    if (q['aviso'] != null) _abrirDesdeEnlace(q['aviso']!, int.tryParse(q['pedido'] ?? ''));
    try {
      await Firebase.initializeApp(options: firebaseWeb);
      _listo = true;
    } catch (e) {
      debugPrint('Firebase web no se inició: $e');
      return;
    }
    await registrarDispositivo();
    FirebaseMessaging.instance.onTokenRefresh.listen(_registrar);
  }

  /// Pide el permiso (debe llamarse al tocar un botón) y registra este navegador. Devuelve si quedó activado.
  static Future<bool> activar() async {
    if (!_listo || !_soportado) return false;
    try {
      final r = await FirebaseMessaging.instance.requestPermission();
      if (r.authorizationStatus != AuthorizationStatus.authorized) return false;
      await registrarDispositivo();
      return _ultimoToken != null;
    } catch (e) {
      debugPrint('No se activaron las notificaciones: $e');
      return false;
    }
  }

  /// Registra este navegador en el backend si ya dio permiso (al abrir la web y al iniciar sesión)
  static Future<void> registrarDispositivo() async {
    if (!_listo || _permiso != 'granted') return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registrar(token);
    } catch (e) {
      debugPrint('Sin token de notificaciones web: $e');
    }
  }

  static Future<void> _registrar(String token) async {
    final jwt = await SessionStore.accessToken();
    if (jwt == null) return;
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.baseUrl}/notificaciones/dispositivo'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $jwt'},
        body: jsonEncode({'token': token, 'plataforma': 'web', 'modelo': 'Navegador'}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) _ultimoToken = token;
    } catch (e) {
      debugPrint('No se registró el navegador: $e');
    }
  }

  /// Al cerrar sesión: este navegador deja de recibir los avisos de esa cuenta
  static Future<void> quitarDispositivo(String jwt) async {
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

  /// Abre lo que dice la notificación cuando la sesión ya se restauró (puede tardar un instante al abrir la web)
  static void _abrirDesdeEnlace(String tipo, int? pedidoId) {
    Future<void> intentar(int vez) async {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.read<AuthProvider>().isAuthenticated) {
        await Future.delayed(const Duration(milliseconds: 1200)); // que se arme la página de inicio
        final c = navigatorKey.currentContext;
        // En el computador se abre dentro de la página (la barra de arriba sigue a la vista)
        if (c != null && c.mounted) abrirAviso(contextoDeContenido(c), tipo: tipo, pedidoId: pedidoId);
      } else if (vez < 200) { // hasta 1 minuto: si no tenía sesión, lo abre al entrar
        Future.delayed(const Duration(milliseconds: 300), () => intentar(vez + 1));
      }
    }

    intentar(0);
  }
}
