import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/pedido.dart';
import 'pedidos_service.dart';
import 'tiempo_real.dart';

/// GPS del repartidor: mientras está en línea o lleva un pedido, manda su posición al servidor (que la reenvía solo
/// al cliente y al negocio de su entrega en curso).
///   * Por socket cada vez que se mueve 10 m, como máximo cada 3 s; si no se mueve, repite la última cada 15 s.
///   * Si el socket no está conectado, usa el respaldo por HTTP (como máximo cada 15 s).
class GpsRepartidor {
  GpsRepartidor._();
  static final GpsRepartidor instancia = GpsRepartidor._();

  StreamSubscription<Position>? _gps;
  Timer? _latido;
  Position? _ultima;
  DateTime _ultimoEnvio = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoHttp = DateTime.fromMillisecondsSinceEpoch(0);
  final _posiciones = StreamController<Punto>.broadcast();

  bool get activo => _gps != null;
  Punto? get ultima => _ultima == null ? null : Punto(_ultima!.latitude, _ultima!.longitude);

  /// La posición propia, para dibujarla en el mapa de la entrega
  Stream<Punto> get posiciones => _posiciones.stream;

  /// Pide permiso de ubicación. Devuelve un mensaje para el usuario si no se puede usar el GPS.
  static Future<String?> verificarPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'Activa la ubicación (GPS) de tu celular para repartir';
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
    if (permiso == LocationPermission.denied) return 'Necesitamos tu ubicación para mostrarle al cliente dónde va su pedido';
    if (permiso == LocationPermission.deniedForever) return 'Permite la ubicación de ValleXpress en los ajustes del celular';
    return null;
  }

  Future<String?> iniciar() async {
    if (_gps != null) return null;
    final problema = await verificarPermiso();
    if (problema != null) return problema;

    _gps = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen(
      (p) => _enviar(p),
      onError: (e) => debugPrint('GPS repartidor: $e'),
    );
    _latido = Timer.periodic(const Duration(seconds: 15), (_) {
      final p = _ultima;
      if (p != null) _enviar(p, forzar: true);
    });
    try {
      _enviar(await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)), forzar: true);
    } catch (_) {
      // la primera posición llegará con el flujo del GPS
    }
    return null;
  }

  Future<void> _enviar(Position p, {bool forzar = false}) async {
    _ultima = p;
    _posiciones.add(Punto(p.latitude, p.longitude));
    final ahora = DateTime.now();
    if (!forzar && ahora.difference(_ultimoEnvio) < const Duration(seconds: 3)) return;
    _ultimoEnvio = ahora;
    final ok = await TiempoReal.instancia.enviarUbicacion(
      lat: p.latitude,
      lng: p.longitude,
      precision: p.accuracy,
      velocidad: p.speed < 0 ? null : p.speed,
      rumbo: p.heading < 0 ? null : p.heading,
    );
    if (!ok && ahora.difference(_ultimoHttp) >= const Duration(seconds: 15)) {
      _ultimoHttp = ahora;
      PedidosService.enviarUbicacion(p.latitude, p.longitude).catchError((_) {});
    }
  }

  void detener() {
    _gps?.cancel();
    _gps = null;
    _latido?.cancel();
    _latido = null;
  }
}
