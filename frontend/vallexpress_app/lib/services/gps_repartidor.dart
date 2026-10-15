import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/pedido.dart';
import 'pedidos_service.dart';
import 'tiempo_real.dart';

/// GPS del repartidor: mientras está en línea o lleva un pedido, manda su posición al servidor (que la reenvía solo
/// al cliente y al negocio de su entrega en curso).
///   * Por socket cada vez que se mueve 10 m, como máximo cada 3 s. Una posición que llega antes de esos 3 s no
///     se pierde: se manda al cumplirse (así la última antes de frenar siempre llega).
///   * Detenido (semáforo, esperando en el local) no manda nada: solo un latido cada 30 s para seguir "visible".
///   * Los saltos del GPS con mala señal (se "mueve" menos que su propio margen de error) se ignoran.
///   * Si el socket no está conectado, usa el respaldo por HTTP (como máximo cada 15 s).
class GpsRepartidor {
  GpsRepartidor._();
  static final GpsRepartidor instancia = GpsRepartidor._();

  static const _minimoEntreEnvios = Duration(seconds: 3);
  static const _latidoDetenido = Duration(seconds: 30);

  StreamSubscription<Position>? _gps;
  Timer? _latido;
  Timer? _pendiente;
  Position? _ultima;
  Position? _ultimaEnviada;
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
      _alMoverse,
      onError: (e) => debugPrint('GPS repartidor: $e'),
    );
    _latido = Timer.periodic(const Duration(seconds: 10), (_) {
      final p = _ultima;
      if (p != null && DateTime.now().difference(_ultimoEnvio) >= _latidoDetenido) _enviar(p);
    });
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      _ultima = p;
      _posiciones.add(Punto(p.latitude, p.longitude));
      _enviar(p);
    } catch (_) {
      // la primera posición llegará con el flujo del GPS
    }
    return null;
  }

  void _alMoverse(Position p) {
    final anterior = _ultimaEnviada;
    // Con mala señal la posición "baila" aunque esté quieto: si se movió menos que el margen de error, se ignora
    if (anterior != null && p.accuracy > 20) {
      final metros = Geolocator.distanceBetween(anterior.latitude, anterior.longitude, p.latitude, p.longitude);
      if (metros < p.accuracy) return;
    }
    _ultima = p;
    _posiciones.add(Punto(p.latitude, p.longitude));
    final espera = _minimoEntreEnvios - DateTime.now().difference(_ultimoEnvio);
    if (espera <= Duration.zero) {
      _enviar(p);
    } else {
      _pendiente ??= Timer(espera, () {
        _pendiente = null;
        final ultima = _ultima;
        if (ultima != null) _enviar(ultima);
      });
    }
  }

  Future<void> _enviar(Position p) async {
    final ahora = DateTime.now();
    _ultimoEnvio = ahora;
    _ultimaEnviada = p;
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
    _pendiente?.cancel();
    _pendiente = null;
    _ultimaEnviada = null;
  }
}
