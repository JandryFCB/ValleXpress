import 'package:flutter/material.dart';
import '../config/theme.dart';

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
String? _texto(Object? v) => (v == null || '$v'.trim().isEmpty) ? null : '$v';
DateTime? _fecha(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Estado de un pedido. El servidor lo maneja como texto ('pendiente', 'en_camino'...).
/// [paso] ubica el estado en la barra de progreso del cliente (-1 = fuera del camino normal).
enum EstadoPedido {
  pendiente('pendiente', 'Esperando confirmación', 'El negocio está revisando tu pedido', Icons.hourglass_top_rounded, AppTheme.warningColor, 0),
  confirmado('confirmado', 'Confirmado', 'El negocio aceptó tu pedido', Icons.thumb_up_alt_rounded, AppTheme.infoColor, 1),
  preparando('preparando', 'Preparando', 'Están preparando tu pedido', Icons.soup_kitchen_rounded, AppTheme.infoColor, 2),
  listo('listo', 'Listo para salir', 'Tu pedido está listo y pronto saldrá hacia ti', Icons.inventory_2_rounded, AppTheme.accentSecondary, 3),
  enCamino('en_camino', 'Repartidor asignado', 'Un repartidor va a recoger tu pedido', Icons.two_wheeler_rounded, AppTheme.accentSecondary, 3),
  recogido('recogido', 'En camino', 'Tu pedido va hacia ti', Icons.delivery_dining_rounded, AppTheme.accentSecondary, 4),
  entregado('entregado', 'Entregado', 'El repartidor dejó tu pedido. ¿Ya lo tienes?', Icons.where_to_vote_rounded, AppTheme.successColor, 5),
  recibido('recibido', 'Recibido', '¡Buen provecho!', Icons.check_circle_rounded, AppTheme.successColor, 5),
  rechazado('rechazado', 'Rechazado', 'El negocio no pudo atender tu pedido', Icons.cancel_rounded, AppTheme.errorColor, -1),
  cancelado('cancelado', 'Cancelado', 'Cancelaste este pedido', Icons.block_rounded, AppTheme.errorColor, -1);

  const EstadoPedido(this.codigo, this.etiqueta, this.descripcion, this.icono, this.color, this.paso);

  final String codigo;
  final String etiqueta;
  final String descripcion;
  final IconData icono;
  final Color color;
  final int paso;

  static EstadoPedido deCodigo(String? c) => EstadoPedido.values.firstWhere((e) => e.codigo == c, orElse: () => EstadoPedido.pendiente);

  /// Sigue en curso (no terminó ni se canceló)
  bool get activo => !const {EstadoPedido.recibido, EstadoPedido.rechazado, EstadoPedido.cancelado}.contains(this);
  bool get fallido => this == EstadoPedido.rechazado || this == EstadoPedido.cancelado;

  /// Pasos de la barra de progreso que ve el cliente
  static const pasos = ['Pedido hecho', 'Confirmado', 'Preparando', 'Listo', 'En camino', 'Entregado'];
}

/// Método de pago ('efectivo', 'transferencia')
class MetodoPago {
  const MetodoPago(this.codigo, this.descripcion);

  final String codigo;
  final String descripcion;

  IconData get icono => switch (codigo) {
        'efectivo' => Icons.payments_rounded,
        'transferencia' => Icons.account_balance_rounded,
        'tarjeta' => Icons.credit_card_rounded,
        _ => Icons.wallet_rounded,
      };

  static String nombre(String? codigo) => switch (codigo) {
        'efectivo' => 'Efectivo',
        'transferencia' => 'Transferencia',
        'tarjeta' => 'Tarjeta',
        'paypal' => 'PayPal',
        _ => codigo ?? '',
      };

  factory MetodoPago.desdeJson(Map<String, dynamic> j) => MetodoPago('${j['codigo']}', '${j['descripcion']}');
}

/// Un producto dentro del pedido (con el precio de cuando se pidió)
class LineaPedido {
  const LineaPedido({required this.productoId, required this.nombre, required this.precioUnitario, required this.cantidad, required this.subtotal, this.notas, this.imagen});

  final int productoId;
  final String nombre;
  final double precioUnitario;
  final int cantidad;
  final double subtotal;
  final String? notas;
  final String? imagen;

  factory LineaPedido.desdeJson(Map<String, dynamic> j) => LineaPedido(
        productoId: (j['productoId'] as num).toInt(),
        nombre: '${j['nombre'] ?? ''}',
        precioUnitario: _num(j['precioUnitario']),
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
        subtotal: _num(j['subtotal']),
        notas: _texto(j['notas']),
        imagen: _texto(j['imagen']),
      );
}

/// Persona de contacto (cliente o repartidor)
class Contacto {
  const Contacto({required this.nombre, this.apellido, this.telefono});

  final String nombre;
  final String? apellido;
  final String? telefono;

  String get nombreCompleto => [nombre, apellido].whereType<String>().join(' ');

  static Contacto? desdeJson(Object? j) {
    if (j is! Map) return null;
    return Contacto(nombre: '${j['nombre'] ?? ''}', apellido: _texto(j['apellido']), telefono: _texto(j['telefono']));
  }
}

/// Un pedido. [lineaTiempo] (cuándo pasó por cada estado) solo llega en el detalle.
class Pedido {
  const Pedido({
    required this.id,
    required this.estado,
    required this.negocioId,
    required this.negocioNombre,
    required this.total,
    this.fecha,
    this.negocioLogo,
    this.direccionEntrega = '',
    this.referenciaEntrega,
    this.metodoPago,
    this.pagado = false,
    this.subtotal = 0,
    this.costoEnvio = 0,
    this.descuento = 0,
    this.propina = 0,
    this.notas,
    this.tiempoEstimado,
    this.motivoCancelacion,
    this.productos = const [],
    this.cantidadProductos = 0,
    this.lineaTiempo = const {},
    this.calificacion,
    this.comentarioCalificacion,
    this.cliente,
    this.repartidor,
  });

  final int id;
  final EstadoPedido estado;
  final DateTime? fecha;
  final int negocioId;
  final String negocioNombre;
  final String? negocioLogo;
  final String direccionEntrega;
  final String? referenciaEntrega;
  final String? metodoPago;
  final bool pagado;
  final double subtotal;
  final double costoEnvio;
  final double descuento;
  final double propina;
  final double total;
  final String? notas;
  final int? tiempoEstimado;
  final String? motivoCancelacion;
  final List<LineaPedido> productos;
  final int cantidadProductos;

  /// Cuándo entró a cada estado (código del estado -> fecha)
  final Map<String, DateTime> lineaTiempo;

  /// Estrellas que el cliente le dio al negocio (null si aún no calificó)
  final int? calificacion;
  final String? comentarioCalificacion;
  final Contacto? cliente;
  final Contacto? repartidor;

  bool get puedeCancelar => estado == EstadoPedido.pendiente;
  bool get puedeConfirmarRecibido => estado == EstadoPedido.entregado;
  bool get puedeCalificar => (estado == EstadoPedido.entregado || estado == EstadoPedido.recibido) && calificacion == null;

  /// Hora aproximada de llegada, a partir de cuando se hizo el pedido
  DateTime? get llegadaEstimada => (fecha == null || tiempoEstimado == null) ? null : fecha!.add(Duration(minutes: tiempoEstimado!));

  /// Resumen corto de los productos: "2× Pizza margarita, 1× Cola"
  String get resumenProductos => productos.map((l) => '${l.cantidad}× ${l.nombre}').join(', ');

  factory Pedido.desdeJson(Map<String, dynamic> j) {
    final negocio = j['negocio'] is Map ? Map<String, dynamic>.from(j['negocio']) : const <String, dynamic>{};
    final entrega = j['entrega'] is Map ? Map<String, dynamic>.from(j['entrega']) : const <String, dynamic>{};
    final calif = j['calificacion'] is Map ? Map<String, dynamic>.from(j['calificacion']) : null;
    return Pedido(
      id: (j['id'] as num).toInt(),
      estado: EstadoPedido.deCodigo(j['estado']?.toString()),
      fecha: _fecha(j['fecha']),
      negocioId: (negocio['id'] as num?)?.toInt() ?? 0,
      negocioNombre: '${negocio['nombre'] ?? ''}',
      negocioLogo: _texto(negocio['logo']),
      direccionEntrega: '${entrega['direccion'] ?? ''}',
      referenciaEntrega: _texto(entrega['referencia']),
      metodoPago: _texto(j['metodoPago']),
      pagado: j['pagado'] == true,
      subtotal: _num(j['subtotal']),
      costoEnvio: _num(j['costoEnvio']),
      descuento: _num(j['descuento']),
      propina: _num(j['propina']),
      total: _num(j['total']),
      notas: _texto(j['notas']),
      tiempoEstimado: (j['tiempoEstimado'] as num?)?.toInt(),
      motivoCancelacion: _texto(j['motivoCancelacion']),
      productos: (j['productos'] as List? ?? []).map((l) => LineaPedido.desdeJson(Map<String, dynamic>.from(l))).toList(),
      cantidadProductos: (j['cantidadProductos'] as num?)?.toInt() ?? 0,
      lineaTiempo: {
        for (final p in (j['lineaTiempo'] as List? ?? []))
          if (p is Map && _fecha(p['fecha']) != null) '${p['estado']}': _fecha(p['fecha'])!,
      },
      calificacion: (calif?['puntuacion'] as num?)?.toInt(),
      comentarioCalificacion: _texto(calif?['comentario']),
      cliente: Contacto.desdeJson(j['cliente']),
      repartidor: Contacto.desdeJson(j['repartidor']),
    );
  }
}

/// Un aviso de la lista de notificaciones
class Aviso {
  const Aviso({required this.id, required this.tipo, required this.titulo, required this.mensaje, this.pedidoId, this.leida = false, this.fecha});

  final int id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final int? pedidoId;
  final bool leida;
  final DateTime? fecha;

  Aviso marcada() => Aviso(id: id, tipo: tipo, titulo: titulo, mensaje: mensaje, pedidoId: pedidoId, leida: true, fecha: fecha);

  IconData get icono => switch (tipo) {
        'pedido_nuevo' => Icons.shopping_bag_rounded,
        'pedido_confirmado' => Icons.thumb_up_alt_rounded,
        'pedido_preparando' => Icons.soup_kitchen_rounded,
        'pedido_listo' => Icons.inventory_2_rounded,
        'pedido_en_camino' || 'pedido_recogido' => Icons.delivery_dining_rounded,
        'pedido_entregado' || 'pedido_recibido' => Icons.check_circle_rounded,
        'pedido_rechazado' || 'pedido_cancelado' => Icons.cancel_rounded,
        _ => Icons.notifications_rounded,
      };

  Color get color => switch (tipo) {
        'pedido_rechazado' || 'pedido_cancelado' => AppTheme.errorColor,
        'pedido_nuevo' => AppTheme.accentColor,
        'pedido_entregado' || 'pedido_recibido' => AppTheme.successColor,
        _ => AppTheme.infoColor,
      };

  factory Aviso.desdeJson(Map<String, dynamic> j) => Aviso(
        id: (j['id'] as num).toInt(),
        tipo: '${j['tipo'] ?? ''}',
        titulo: '${j['titulo'] ?? ''}',
        mensaje: '${j['mensaje'] ?? ''}',
        pedidoId: (j['pedidoId'] as num?)?.toInt(),
        leida: j['leida'] == true,
        fecha: _fecha(j['fecha']),
      );
}
