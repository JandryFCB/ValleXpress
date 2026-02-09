import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

String? _currentToken;
String? _currentBaseUrl;

class TrackingSocketService {
  static final TrackingSocketService _instance =
      TrackingSocketService._internal();
  factory TrackingSocketService() => _instance;
  TrackingSocketService._internal();

  IO.Socket? _socket;
  String? _lastJoinedPedidoId;

  StreamController<Map<String, dynamic>>? _locationController;
  StreamController<Map<String, dynamic>>? _notificationController;

  Stream<Map<String, dynamic>> get locationStream {
    _locationController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _locationController!.stream;
  }

  Stream<Map<String, dynamic>> get notificationStream {
    _notificationController ??=
        StreamController<Map<String, dynamic>>.broadcast();
    return _notificationController!.stream;
  }

  bool get isConnected => _socket?.connected ?? false;

  void connect({required String baseUrl, required String token}) {
    // Si el token o baseUrl cambió, hay que recrear el socket (handshake nuevo)
    if (_socket != null &&
        (_currentToken != token || _currentBaseUrl != baseUrl)) {
      try {
        _socket!.disconnect();
      } catch (_) {}
      _socket = null;
      _lastJoinedPedidoId = null;
    }
    _currentToken = token;
    _currentBaseUrl = baseUrl;

    if (_socket != null) {
      try {
        _socket!.auth = {'token': token};
      } catch (_) {}
      if (!(_socket!.connected) && !(_socket!.active)) {
        _socket!.connect();
      }
      return;
    }

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setRandomizationFactor(0.5)
          .setAuth({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      if (kDebugMode) print('🟢 Socket conectado');
      if (_lastJoinedPedidoId != null) {
        try {
          _socket!.emit('pedido:join', {'pedidoId': _lastJoinedPedidoId});
        } catch (_) {}
      }
    });

    _socket!.onDisconnect((reason) {
      if (kDebugMode) print('🔴 Socket desconectado: $reason');
    });

    _socket!.on('reconnect_attempt', (n) {
      if (kDebugMode) print('… Reintentando socket ($n)');
    });
    _socket!.on('reconnect', (_) {
      if (kDebugMode) print('🟢 Socket reconectado');
      if (_lastJoinedPedidoId != null) {
        try {
          _socket!.emit('pedido:join', {'pedidoId': _lastJoinedPedidoId});
        } catch (_) {}
      }
    });

    _socket!.on('reconnect_error', (e) {
      if (kDebugMode) print('❌ reconnect_error: $e');
    });
    _socket!.on('reconnect_failed', (_) {
      if (kDebugMode) print('❌ reconnect_failed');
    });
    _socket!.onConnectError((e) {
      if (kDebugMode) print('❌ connect_error: $e');
    });
    _socket!.onError((e) {
      if (kDebugMode) print('❌ error: $e');
    });

    // Escuchar notificaciones en tiempo real
    _socket!.on('notificacion', (data) {
      try {
        if (kDebugMode) {
          print(
            '🔔 RAW notificacion recibida => type=${data.runtimeType} value=$data',
          );
        }

        // Verificar que el controller esté activo
        if (_notificationController == null ||
            _notificationController!.isClosed) {
          if (kDebugMode) {
            print('⚠️ NotificationController cerrado, ignorando evento');
          }
          return;
        }

        if (data is Map) {
          _notificationController!.add(Map<String, dynamic>.from(data));
          return;
        }

        // Fallback para web
        try {
          final encoded = jsonEncode(data);
          final decoded = jsonDecode(encoded);
          if (decoded is Map) {
            _notificationController!.add(Map<String, dynamic>.from(decoded));
            return;
          }
        } catch (_) {}

        if (data is String) {
          final parsed = jsonDecode(data);
          if (parsed is Map) {
            _notificationController!.add(Map<String, dynamic>.from(parsed));
            return;
          }
        }

        if (data is List && data.isNotEmpty) {
          final first = data[0];
          if (first is Map) {
            _notificationController!.add(Map<String, dynamic>.from(first));
            return;
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error parseando notificacion => $e');
      }
    });

    _socket!.on('pedido:ubicacion', (data) {
      // Debug: mostrar raw data y tipo para diagnosticar problemas de parsing
      try {
        if (kDebugMode) {
          print(
            '🔔 RAW pedido:ubicacion recibido => type=${data.runtimeType} value=$data',
          );
        }
      } catch (_) {}

      try {
        // Verificar que el controller esté activo
        if (_locationController == null || _locationController!.isClosed) {
          if (kDebugMode) {
            print('⚠️ LocationController cerrado, ignorando evento');
          }
          return;
        }

        if (data is Map) {
          _locationController!.add(Map<String, dynamic>.from(data));
          return;
        }
        // En Flutter web, el payload puede venir como un objeto JS (_JsObject).
        // Intentar convertir por jsonEncode/jsonDecode como fallback.
        try {
          final encoded = jsonEncode(data);
          final decoded = jsonDecode(encoded);
          if (decoded is Map) {
            _locationController!.add(Map<String, dynamic>.from(decoded));
            return;
          }
        } catch (_) {}

        if (data is String) {
          final parsed = jsonDecode(data);
          if (parsed is Map) {
            _locationController!.add(Map<String, dynamic>.from(parsed));
            return;
          }
        }

        if (data is List) {
          // Socket.IO web frecuentemente entrega [payload, socketId]
          // -> preferimos usar el primer elemento si existe.
          if (data.isNotEmpty) {
            final first = data[0];
            try {
              if (first is Map) {
                _locationController!.add(Map<String, dynamic>.from(first));
                return;
              }
              // Intentar convertir objetos JS a JSON
              final encodedFirst = jsonEncode(first);
              final decodedFirst = jsonDecode(encodedFirst);
              if (decodedFirst is Map) {
                _locationController!.add(
                  Map<String, dynamic>.from(decodedFirst),
                );
                return;
              }
            } catch (_) {}
          }

          // Fallback antiguo: intentar convertir pares [k,v,k,v,...]
          final m = <String, dynamic>{};
          for (var i = 0; i + 1 < data.length; i += 2) {
            final k = data[i]?.toString() ?? i.toString();
            m[k] = data[i + 1];
          }
          if (m.isNotEmpty) {
            _locationController!.add(m);
            return;
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error parseando pedido:ubicacion => $e');
      }
    });
  }

  Future<void> ensureConnected() async {
    if (_socket == null) return;
    if (!(_socket!.connected)) {
      try {
        _socket!.connect();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> joinPedido(String pedidoId) async {
    if (_socket == null) return {'ok': false, 'error': 'SOCKET_NULL'};

    final completer = Completer<Map<String, dynamic>>();
    await ensureConnected();
    _lastJoinedPedidoId = pedidoId;

    _socket!.emitWithAck(
      'pedido:join',
      {'pedidoId': pedidoId},
      ack: (res) {
        if (res is Map) {
          completer.complete(Map<String, dynamic>.from(res));
        } else {
          completer.complete({'ok': false, 'error': 'ACK_INVALIDO'});
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => {'ok': false, 'error': 'TIMEOUT_JOIN'},
    );
  }

  Future<Map<String, dynamic>> sendDriverLocation({
    required String pedidoId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    double? accuracy,
    int? ts,
  }) async {
    if (_socket == null) return {'ok': false, 'error': 'SOCKET_NULL'};

    final payload = <String, dynamic>{
      'pedidoId': pedidoId,
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
      if (ts != null) 'ts': ts,
    };

    final completer = Completer<Map<String, dynamic>>();

    _socket!.emitWithAck(
      'repartidor:ubicacion',
      payload,
      ack: (res) {
        if (res is Map) {
          completer.complete(Map<String, dynamic>.from(res));
        } else {
          completer.complete({'ok': false, 'error': 'ACK_INVALIDO'});
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => {'ok': false, 'error': 'TIMEOUT_UBICACION'},
    );
  }

  void disconnect() => _socket?.disconnect();

  /// Limpia completamente el estado del singleton (usar al cerrar sesión)
  void reset() {
    try {
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _lastJoinedPedidoId = null;
    _currentToken = null;
    _currentBaseUrl = null;
  }

  void dispose() {
    // No cerrar los controllers permanentemente - solo limpiar listeners
    // Los controllers se recrearán automáticamente cuando se necesiten
    _notificationController?.close();
    _notificationController = null;
    _locationController?.close();
    _locationController = null;
  }
}
