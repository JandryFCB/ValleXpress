import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';
import '../models/pedido.dart';
import 'session_manager.dart';
import 'session_store.dart';

/// Conexión en tiempo real con el servidor (Socket.IO). El servidor avisa a cada usuario en su sala `user:<usuario>`:
///   * 'pedido:actualizado' { pedidoId, estado }  -> las pantallas de pedidos se recargan solas
///   * 'notificacion' (un aviso)                   -> el contador de la campana sube y se muestra un mensaje
/// La conexión usa el token de acceso vigente; si el servidor lo rechaza por vencido, se renueva y se reconecta.
class TiempoReal {
  TiempoReal._();
  static final TiempoReal instancia = TiempoReal._();

  io.Socket? _socket;
  StreamSubscription<String>? _renovado;
  bool _renovando = false;

  final _pedidos = StreamController<({int pedidoId, EstadoPedido estado})>.broadcast();
  final _avisos = StreamController<Aviso>.broadcast();
  final _ubicaciones = StreamController<({int pedidoId, Punto punto, double? rumbo, double? velocidadKmh})>.broadcast();

  /// Posición del repartidor de un pedido en curso (la reciben su cliente y el negocio)
  Stream<({int pedidoId, Punto punto, double? rumbo, double? velocidadKmh})> get ubicaciones => _ubicaciones.stream;

  /// Cambios de estado de cualquier pedido del usuario
  Stream<({int pedidoId, EstadoPedido estado})> get pedidos => _pedidos.stream;

  /// Avisos nuevos (los mismos que llegan a la lista de notificaciones)
  Stream<Aviso> get avisos => _avisos.stream;

  bool get conectado => _socket?.connected ?? false;

  /// Cuándo recargar una pantalla: un cambio de estado (de ese pedido, o de cualquiera si no se indica) o el
  /// regreso de la app desde segundo plano, porque lo que pasó mientras el socket dormía no llegó por él.
  Stream<void> cambios({int? pedidoId}) {
    final subs = <StreamSubscription>[];
    late final StreamController<void> c;
    c = StreamController<void>(
      onListen: () {
        subs.add(pedidos.where((e) => pedidoId == null || e.pedidoId == pedidoId).listen((_) => c.add(null)));
        subs.add(_reanudado.stream.listen((_) => c.add(null)));
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return c.stream;
  }

  final _reanudado = StreamController<void>.broadcast();
  _Ciclo? _ciclo;

  /// Conecta (o reconecta con el token actual). Se llama al entrar a la app con sesión.
  Future<void> iniciar() async {
    _ciclo ??= _Ciclo(_alVolver)..escuchar();
    var token = await SessionStore.accessToken();
    if (token != null && !SessionStore.accesoVigente(token) && await SessionManager.instance.refrescar()) {
      token = await SessionStore.accessToken();
    }
    if (token == null) return;

    // Cada renovación de la sesión trae un token nuevo: la próxima reconexión debe usarlo
    _renovado ??= SessionManager.instance.renovado.listen((nuevo) => _socket?.auth = {'token': nuevo});

    if (_socket != null) {
      _socket!.auth = {'token': token};
      if (!_socket!.connected) _socket!.connect();
      return;
    }

    final s = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .disableAutoConnect()
          .build(),
    );
    s.onConnect((_) => debugPrint('🟢 Tiempo real conectado'));
    s.onDisconnect((motivo) => debugPrint('🔴 Tiempo real desconectado: $motivo'));
    s.onConnectError((e) => _alFallar('$e'));
    s.on('pedido:actualizado', (crudo) {
      final datos = _mapa(crudo);
      final id = (datos?['pedidoId'] as num?)?.toInt();
      if (id != null) _pedidos.add((pedidoId: id, estado: EstadoPedido.deCodigo(datos!['estado']?.toString())));
    });
    s.on('notificacion', (crudo) {
      final datos = _mapa(crudo);
      if (datos?['id'] != null) _avisos.add(Aviso.desdeJson(datos!));
    });
    s.on('pedido:ubicacion', (crudo) {
      final datos = _mapa(crudo);
      final id = (datos?['pedidoId'] as num?)?.toInt();
      final punto = Punto.desdeJson(datos);
      if (id != null && punto != null) {
        _ubicaciones.add((pedidoId: id, punto: punto, rumbo: (datos!['rumbo'] as num?)?.toDouble(), velocidadKmh: (datos['velocidadKmh'] as num?)?.toDouble()));
      }
    });
    _socket = s..connect();
  }

  // socket_io_client entrega los datos del evento a veces sueltos y a veces dentro de una lista ([ {...} ])
  static Map<String, dynamic>? _mapa(Object? crudo) {
    final valor = crudo is List && crudo.isNotEmpty ? crudo.first : crudo;
    return valor is Map ? Map<String, dynamic>.from(valor) : null;
  }

  // El servidor rechaza un token vencido con INVALID_TOKEN: se renueva la sesión y se reintenta una vez
  Future<void> _alFallar(String error) async {
    if (!error.contains('INVALID_TOKEN') || _renovando) return;
    _renovando = true;
    try {
      if (await SessionManager.instance.refrescar()) {
        _socket?.auth = {'token': await SessionStore.accessToken()};
        _socket?.connect();
      }
    } finally {
      _renovando = false;
    }
  }

  /// El repartidor envía su posición. Devuelve false si no hay conexión (se usa el respaldo por HTTP).
  Future<bool> enviarUbicacion({required double lat, required double lng, double? precision, double? velocidad, double? rumbo}) async {
    final s = _socket;
    if (s == null || !s.connected) return false;
    final respuesta = Completer<bool>();
    s.emitWithAck('repartidor:ubicacion', {'lat': lat, 'lng': lng, 'precision': precision, 'velocidad': velocidad, 'rumbo': rumbo}, ack: (r) {
      final datos = _mapa(r);
      if (!respuesta.isCompleted) respuesta.complete(datos?['ok'] == true || datos?['error'] == 'MUYFRECUENTE');
    });
    return respuesta.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
  }

  // La app volvió al frente: se reconecta de inmediato (sin esperar el siguiente reintento) y las pantallas
  // abiertas se recargan para traer el estado y la última ubicación conocida del repartidor.
  Future<void> _alVolver() async {
    if (_socket == null) return;
    await iniciar();
    _reanudado.add(null);
  }

  /// Al cerrar sesión: se corta la conexión (otro usuario no debe recibir estos avisos)
  void detener() {
    _ciclo?.dejar();
    _ciclo = null;
    _socket?.dispose();
    _socket = null;
    _renovado?.cancel();
    _renovado = null;
  }
}

/// Avisa cuando la app pasa de segundo plano al frente
class _Ciclo with WidgetsBindingObserver {
  _Ciclo(this.alVolver);

  final Future<void> Function() alVolver;

  void escuchar() => WidgetsBinding.instance.addObserver(this);
  void dejar() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) alVolver();
  }
}
