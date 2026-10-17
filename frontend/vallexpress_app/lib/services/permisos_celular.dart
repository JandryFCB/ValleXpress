import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Qué le falta a un permiso del celular y qué se puede hacer
enum EstadoPermiso {
  listo,
  pedir, // se puede pedir con el diálogo del sistema
  ajustes, // el usuario lo negó para siempre: solo desde los ajustes del celular
  gpsApagado, // la ubicación del celular está apagada
  aproximada, // dio permiso, pero solo ubicación aproximada (el mapa del cliente quedaría mal)
}

/// Permisos que necesita cada rol para trabajar bien:
///   * repartidor: ubicación precisa, notificaciones y batería sin restricciones (que Android no corte el GPS)
///   * vendedor y cliente: notificaciones (que suene el pedido nuevo / el estado de su pedido)
/// En la web no hay nada que pedir: todo cuenta como listo.
class PermisosCelular {
  static const _bateria = MethodChannel('vallexpress/bateria');
  static bool get _movil => !kIsWeb;
  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool necesitaUbicacion(String? rol) => rol == 'repartidor';
  static bool necesitaBateria(String? rol) => rol == 'repartidor' && _android;

  // ---------------------------------------------------------------------------------------------
  // Ubicación
  // ---------------------------------------------------------------------------------------------
  static Future<EstadoPermiso> ubicacion() async {
    if (!_movil) return EstadoPermiso.listo;
    if (!await Geolocator.isLocationServiceEnabled()) return EstadoPermiso.gpsApagado;
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.deniedForever) return EstadoPermiso.ajustes;
    if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) return EstadoPermiso.pedir;
    try {
      if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) return EstadoPermiso.aproximada;
    } catch (_) {}
    return EstadoPermiso.listo;
  }

  static Future<void> resolverUbicacion(EstadoPermiso e) async {
    switch (e) {
      case EstadoPermiso.gpsApagado:
        await Geolocator.openLocationSettings();
      case EstadoPermiso.ajustes:
        await Geolocator.openAppSettings();
      case EstadoPermiso.pedir || EstadoPermiso.aproximada:
        final p = await Geolocator.requestPermission();
        if (p == LocationPermission.deniedForever) await Geolocator.openAppSettings();
      case EstadoPermiso.listo:
        break;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Notificaciones
  // ---------------------------------------------------------------------------------------------
  static Future<EstadoPermiso> notificaciones() async {
    if (!_movil) return EstadoPermiso.listo;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (s.authorizationStatus) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => EstadoPermiso.listo,
        AuthorizationStatus.notDetermined => EstadoPermiso.pedir,
        AuthorizationStatus.denied => EstadoPermiso.ajustes,
      };
    } catch (_) {
      return EstadoPermiso.listo; // sin Firebase no hay nada que pedir
    }
  }

  static Future<void> resolverNotificaciones(EstadoPermiso e) async {
    if (e == EstadoPermiso.listo) return;
    final s = await FirebaseMessaging.instance.requestPermission();
    // Android deja de mostrar el diálogo después de dos "No": entonces se va a los ajustes
    if (s.authorizationStatus == AuthorizationStatus.denied) await Geolocator.openAppSettings();
  }

  // ---------------------------------------------------------------------------------------------
  // Batería (solo Android)
  // ---------------------------------------------------------------------------------------------
  static Future<EstadoPermiso> bateria() async {
    if (!_android) return EstadoPermiso.listo;
    try {
      return await _bateria.invokeMethod<bool>('sinRestricciones') == true ? EstadoPermiso.listo : EstadoPermiso.ajustes;
    } catch (_) {
      return EstadoPermiso.listo;
    }
  }

  static Future<void> abrirAjustesBateria() async {
    try {
      await _bateria.invokeMethod('abrirAjustes');
    } catch (_) {
      await Geolocator.openAppSettings();
    }
  }

  // ---------------------------------------------------------------------------------------------
  /// ¿Le falta algo a este rol? (para mostrar el aviso "Prepara tu celular")
  static Future<bool> faltaAlgo(String? rol) async {
    if (!_movil) return false;
    if (await notificaciones() != EstadoPermiso.listo) return true;
    if (necesitaUbicacion(rol) && await ubicacion() != EstadoPermiso.listo) return true;
    if (necesitaBateria(rol) && await bateria() != EstadoPermiso.listo) return true;
    return false;
  }

  /// ¿Puede ponerse en línea? (ubicación y notificaciones son obligatorias; la batería, muy recomendada)
  static Future<bool> listoParaRepartir() async =>
      await ubicacion() == EstadoPermiso.listo && await notificaciones() == EstadoPermiso.listo;
}
