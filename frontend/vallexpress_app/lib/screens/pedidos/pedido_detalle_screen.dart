import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../utils/contacto.dart';
import '../../widgets/mapa_pedido.dart';
import '../../widgets/pago_transferencia.dart';
import '../../widgets/ui/ui.dart';

/// Seguimiento de un pedido: estado actual, barra de progreso con la hora de cada paso, productos, totales y
/// las acciones del cliente (cancelar mientras está pendiente, confirmar que lo recibió y calificar).
/// Se actualiza sola cuando el servidor avisa un cambio de estado (tiempo real).
class PedidoDetalleScreen extends StatefulWidget {
  const PedidoDetalleScreen({super.key, required this.pedidoId, this.inicial, this.recienHecho = false});

  final int pedidoId;

  /// El pedido que ya se tenía (se muestra al instante mientras se recarga)
  final Pedido? inicial;

  /// Se acaba de hacer: se muestra un mensaje de bienvenida
  final bool recienHecho;

  @override
  State<PedidoDetalleScreen> createState() => _PedidoDetalleScreenState();
}

class _PedidoDetalleScreenState extends State<PedidoDetalleScreen> {
  late Pedido? _pedido = widget.inicial;
  String? _error;
  bool _ocupado = false;
  StreamSubscription? _vivo;
  StreamSubscription? _gps;

  /// Última posición del repartidor recibida en vivo (mientras lleva el pedido)
  Punto? _repartidorEn;
  double? _velocidadKmh;

  @override
  void initState() {
    super.initState();
    _cargar();
    if (widget.recienHecho) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? Confeti.lanzar(context) : null);
    _vivo =TiempoReal.instancia.cambios(pedidoId: widget.pedidoId).listen((_) => _cargar());
    _gps = TiempoReal.instancia.ubicaciones.where((u) => u.pedidoId == widget.pedidoId).listen((u) {
      if (!mounted) return;
      setState(() {
        _repartidorEn = u.punto;
        _velocidadKmh = u.velocidadKmh;
      });
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  /// Minutos que le faltan al repartidor, a partir de la distancia que le queda (velocidad real o 20 km/h)
  int? _minutosRestantes(Pedido p) {
    final desde = _repartidorEn ?? p.repartidor?.ubicacion;
    final hasta = p.estado == EstadoPedido.recogido ? p.entregaPunto : p.negocioLocal;
    if (desde == null || hasta == null) return null;
    var km = distanciaKm(desde, hasta);
    if (p.estado == EstadoPedido.enCamino && p.entregaPunto != null && p.negocioLocal != null) km += distanciaKm(p.negocioLocal!, p.entregaPunto!);
    final velocidad = (_velocidadKmh != null && _velocidadKmh! > 8) ? _velocidadKmh! : 20.0;
    return (km * 1.3 / velocidad * 60).ceil().clamp(1, 240);   // 1.3: las calles no van en línea recta
  }

  Future<void> _cargar() async {
    try {
      final p = await PedidosService.obtener(widget.pedidoId);
      if (!mounted) return;
      if (_pedido != null && _pedido!.estado != p.estado) {
        HapticFeedback.mediumImpact();
        if (p.estado == EstadoPedido.entregado) Confeti.lanzar(context);
      }
      setState(() {
        _pedido = p;
        _error = null;
        _repartidorEn = null;     // manda la última ubicación que guardó el servidor; las siguientes llegan en vivo
      });
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _accion(Future<Pedido> Function() fn, String exito) async {
    setState(() => _ocupado = true);
    try {
      final p = await fn();
      if (!mounted) return;
      setState(() => _pedido = p);
      mostrarExito(context, exito);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cancelar() async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar el pedido?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_pedido!.estado == EstadoPedido.pendiente
                ? 'El negocio aún no lo acepta, así que puedes cancelarlo sin problema.'
                : 'Todavía no has transferido, así que puedes cancelarlo sin problema.'),
            const SizedBox(height: 12),
            TextField(controller: motivo, maxLength: 300, decoration: const InputDecoration(hintText: 'Motivo (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir esperando')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Cancelar pedido')),
        ],
      ),
    );
    if (ok == true) await _accion(() => PedidosService.cancelar(widget.pedidoId, motivo: motivo.text), 'Pedido cancelado');
  }

  Future<void> _calificar() async {
    final r = await mostrarHoja<({int estrellas, String comentario})>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaCalificar(negocio: _pedido!.negocioNombre),
    );
    if (r != null) await _accion(() => PedidosService.calificar(widget.pedidoId, puntuacion: r.estrellas, comentario: r.comentario), '¡Gracias por tu calificación!');
  }

  Future<void> _calificarRepartidor() async {
    final r = await mostrarHoja<({int estrellas, String comentario})>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaCalificar(negocio: _pedido!.repartidor!.nombre, pregunta: '¿Qué tal te atendió ${_pedido!.repartidor!.nombre}?'),
    );
    if (r != null) await _accion(() => PedidosService.calificarRepartidor(widget.pedidoId, puntuacion: r.estrellas, comentario: r.comentario), '¡Gracias por tu calificación!');
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    return FondoValle(
      titulo: 'Pedido #${widget.pedidoId}',
      barraInferior: p == null ? null : _barraAcciones(p),
      child: p == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el pedido', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(onRefresh: _cargar, child: _contenido(p)),
    );
  }

  Widget? _barraAcciones(Pedido p) {
    final botones = <Widget>[
      if (p.puedeConfirmarRecibido)
        BotonValle(texto: 'Ya lo recibí', icono: Icons.check_circle_rounded, cargando: _ocupado, onPressed: () => _accion(() => PedidosService.confirmarRecibido(p.id), '¡Que lo disfrutes!')),
      if (p.puedeCalificar) BotonValle(texto: 'Calificar a ${p.negocioNombre}', icono: Icons.star_rounded, tipo: p.puedeConfirmarRecibido ? TipoBoton.secundario : TipoBoton.principal, onPressed: _ocupado ? null : _calificar),
      if (!p.puedeCalificar && p.puedeCalificarRepartidor)
        BotonValle(texto: 'Calificar a ${p.repartidor!.nombre}', icono: Icons.two_wheeler_rounded, tipo: p.puedeConfirmarRecibido ? TipoBoton.secundario : TipoBoton.principal, onPressed: _ocupado ? null : _calificarRepartidor),
      if (p.puedeCancelar) BotonValle(texto: 'Cancelar pedido', icono: Icons.close_rounded, tipo: TipoBoton.peligro, cargando: _ocupado, onPressed: _cancelar),
    ];
    if (botones.isEmpty) return null;
    final c = context.colores;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [for (final (i, b) in botones.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: b)]),
      ),
    );
  }

  Widget _contenido(Pedido p) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final e = p.estado;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (widget.recienHecho && e == EstadoPedido.pendiente)
          Aparecer(
            child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TarjetaValle(
              color: c.primario.withValues(alpha: 0.12),
              colorBorde: c.primario,
              child: Row(
                children: [
                  Icon(Icons.celebration_rounded, color: c.primario, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text('¡Pedido enviado! Te avisaremos en cuanto el negocio lo confirme.', style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),
          ),

        // ---------------------------- Estado actual ----------------------------
        TarjetaValle(
          child: Column(
            children: [
              // Late mientras el pedido avanza; salta al cambiar de estado
              IconoLatiendo(icono: e.icono, color: e.color, activo: e.activo && e != EstadoPedido.entregado, tamano: 76),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (hijo, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: hijo),
                ),
                child: Column(
                  key: ValueKey(e),
                  children: [
                    Text(e.etiqueta, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(e == EstadoPedido.cancelado || e == EstadoPedido.rechazado ? (p.motivoCancelacion ?? e.descripcion) : e.descripcion,
                        textAlign: TextAlign.center, style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
                  ],
                ),
              ),
              if (p.enReparto && _minutosRestantes(p) != null) ...[
                const SizedBox(height: 12),
                InsigniaValle('Llega en unos ${_minutosRestantes(p)} min', color: c.primario, icono: Icons.schedule_rounded),
              ] else if (e.activo && e.paso < 5 && p.llegadaEstimada != null) ...[
                const SizedBox(height: 12),
                InsigniaValle('Llega aprox. a las ${Formato.hora(p.llegadaEstimada!)}', color: c.primario, icono: Icons.schedule_rounded),
              ],
              if (!e.fallido) ...[
                const SizedBox(height: 20),
                _Progreso(pedido: p),
              ],
            ],
          ),
        ),

        // ---------------------------- Pago por transferencia ----------------------------
        if (p.esTransferencia && !e.fallido && (e == EstadoPedido.pendiente || e == EstadoPedido.confirmado || p.pagado)) ...[
          const SizedBox(height: 12),
          Aparecer(child: PagoTransferenciaCliente(pedido: p, onActualizado: (n) => setState(() => _pedido = n))),
        ],

        // ---------------------------- Repartidor y mapa en vivo ----------------------------
        if (p.repartidor != null && (p.enReparto || e == EstadoPedido.entregado)) ...[
          const SizedBox(height: 12),
          Aparecer(child: TarjetaRepartidor(repartidor: p.repartidor!)),
        ],
        if (p.enReparto) ...[
          const SizedBox(height: 12),
          Aparecer(
            child: MapaPedido(
            negocio: p.negocioLocal,
            entrega: p.entregaPunto,
            repartidor: _repartidorEn ?? p.repartidor?.ubicacion,
            haciaNegocio: e == EstadoPedido.enCamino,
            iconoRepartidor: p.repartidor?.vehiculo?.icono ?? Icons.two_wheeler_rounded,
          ),
          ),
          if ((_repartidorEn ?? p.repartidor?.ubicacion) == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Esperando la ubicación del repartidor…', textAlign: TextAlign.center, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            ),
        ],

        if (p.calificacion != null) ...[
          const SizedBox(height: 12),
          TarjetaValle(
            child: Row(
              children: [
                for (var i = 1; i <= 5; i++) Icon(i <= p.calificacion! ? Icons.star_rounded : Icons.star_border_rounded, color: AppTheme.accentColor),
                const SizedBox(width: 10),
                Expanded(child: Text(p.comentarioCalificacion ?? 'Tu calificación', style: tema.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],

        // ---------------------------- Productos ----------------------------
        EncabezadoSeccion(p.negocioNombre, subtitulo: p.fecha == null ? null : Formato.fechaRelativa(p.fecha!)),
        TarjetaValle(
          child: Column(
            children: [
              for (final l in p.productos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text('${l.cantidad}×', style: tema.labelLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.nombre, style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                            if (l.notas != null) Text(l.notas!, style: tema.bodySmall?.copyWith(color: c.textoSuave, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      Text(Formato.dinero(l.subtotal), style: tema.bodyMedium),
                    ],
                  ),
                ),
              Divider(height: 1, color: c.borde),
              const SizedBox(height: 10),
              _Monto('Productos', p.subtotal),
              _Monto('Envío', p.costoEnvio),
              if (p.descuento > 0) _Monto('Descuento', -p.descuento),
              if (p.propina > 0) _Monto('Propina', p.propina),
              const SizedBox(height: 4),
              _Monto('Total', p.total, destacado: true),
            ],
          ),
        ),

        // ---------------------------- Entrega y pago ----------------------------
        const EncabezadoSeccion('Entrega y pago'),
        TarjetaValle(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Dato(Icons.location_on_outlined, p.direccionEntrega, p.referenciaEntrega),
              const SizedBox(height: 12),
              _Dato(
                Icons.payments_outlined,
                MetodoPago.nombre(p.metodoPago),
                p.pagado ? 'Pagado' : (p.esTransferencia ? (e.fallido ? 'Sin pagar' : 'Falta confirmar tu transferencia') : 'Se paga al recibir'),
              ),
              if (p.notas != null) ...[const SizedBox(height: 12), _Dato(Icons.chat_bubble_outline_rounded, 'Indicaciones', p.notas)],
              if (p.repartidor != null && !(p.enReparto || e == EstadoPedido.entregado)) ...[
                const SizedBox(height: 12),
                _Dato(p.repartidor!.vehiculo?.icono ?? Icons.two_wheeler_rounded, p.repartidor!.nombreCompleto, 'Te llevó el pedido${p.calificacionRepartidor != null ? ' · le diste ${p.calificacionRepartidor} ★' : ''}'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Barra de progreso del pedido: 6 pasos con la hora en que se cumplió cada uno
class _Progreso extends StatelessWidget {
  const _Progreso({required this.pedido});

  final Pedido pedido;

  // Estados que cumplen cada paso de la barra
  static const _estadosDePaso = [
    ['pendiente'],
    ['confirmado'],
    ['preparando'],
    ['listo', 'en_camino'],
    ['recogido'],
    ['entregado', 'recibido'],
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final actual = pedido.estado.paso;
    return Column(
      children: [
        for (var i = 0; i < EstadoPedido.pasos.length; i++)
          Builder(builder: (_) {
            final hecho = i <= actual;
            final fecha = _estadosDePaso[i].map((e) => pedido.lineaTiempo[e]).whereType<DateTime>().firstOrNull;
            final ultimo = i == EstadoPedido.pasos.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: hecho ? c.primario : c.tarjeta,
                            shape: BoxShape.circle,
                            border: Border.all(color: hecho ? c.primario : c.borde, width: 2),
                          ),
                          child: hecho ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                        ),
                        if (!ultimo) Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 500), width: 2, color: i < actual ? c.primario : c.borde)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(EstadoPedido.pasos[i],
                                style: tema.bodyMedium?.copyWith(fontWeight: i == actual ? FontWeight.w800 : FontWeight.w500, color: hecho ? c.texto : c.textoSuave)),
                          ),
                          if (fecha != null) Text(Formato.hora(fecha), style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _Monto extends StatelessWidget {
  const _Monto(this.etiqueta, this.monto, {this.destacado = false});

  final String etiqueta;
  final double monto;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final estilo = destacado ? tema.titleMedium?.copyWith(fontWeight: FontWeight.w800) : tema.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: estilo)),
          Text(etiqueta == 'Envío' && monto == 0 ? 'Gratis' : Formato.dinero(monto), style: estilo),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.titulo, this.detalle);

  final IconData icono;
  final String titulo;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 20, color: c.primario),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (detalle != null) Text(detalle!, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta del repartidor: nombre, vehículo, calificación y botón para llamarlo
class TarjetaRepartidor extends StatelessWidget {
  const TarjetaRepartidor({super.key, required this.repartidor, this.titulo = 'Tu repartidor'});

  final RepartidorPedido repartidor;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final r = repartidor;
    return TarjetaValle(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: AppTheme.infoColor.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(r.vehiculo?.icono ?? Icons.two_wheeler_rounded, color: AppTheme.infoColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                Row(
                  children: [
                    Flexible(child: Text(r.nombreCompleto, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                    if ((r.calificacion ?? 0) > 0) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, size: 16, color: AppTheme.accentColor),
                      Text(r.calificacion!.toStringAsFixed(1), style: tema.labelMedium),
                    ],
                  ],
                ),
                if (r.descripcionVehiculo.isNotEmpty) Text(r.descripcionVehiculo, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
              ],
            ),
          ),
          if (r.telefono != null)
            IconButton.filledTonal(tooltip: 'Llamar', onPressed: () => llamar(context, r.telefono!), icon: const Icon(Icons.call_rounded)),
        ],
      ),
    );
  }
}

/// Hoja para calificar (al negocio o al repartidor): estrellas y un comentario opcional
/// Pide estrellas y un comentario (opcional). La usa el cliente (negocio y repartidor) y el negocio (repartidor).
Future<({int estrellas, String comentario})?> pedirCalificacion(BuildContext context, {required String nombre, String? pregunta}) =>
    mostrarHoja<({int estrellas, String comentario})>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaCalificar(negocio: nombre, pregunta: pregunta),
    );

class _HojaCalificar extends StatefulWidget {
  const _HojaCalificar({required this.negocio, this.pregunta});

  final String negocio;
  final String? pregunta;

  @override
  State<_HojaCalificar> createState() => _HojaCalificarState();
}

class _HojaCalificarState extends State<_HojaCalificar> {
  int _estrellas = 0;
  final _comentario = TextEditingController();

  static const _textos = ['', 'Malo', 'Regular', 'Bueno', 'Muy bueno', '¡Excelente!'];

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.pregunta ?? '¿Qué tal estuvo ${widget.negocio}?', style: tema.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 42,
                    tooltip: '$i estrella${i == 1 ? '' : 's'}',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _estrellas = i);
                    },
                    icon: Icon(i <= _estrellas ? Icons.star_rounded : Icons.star_border_rounded, color: AppTheme.accentColor),
                  ),
              ],
            ),
            Text(_textos[_estrellas], style: tema.titleSmall?.copyWith(color: AppTheme.accentColor)),
            const SizedBox(height: 12),
            TextField(
              controller: _comentario,
              maxLength: 500,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Cuéntanos más (opcional)'),
            ),
            const SizedBox(height: 8),
            BotonValle(
              texto: 'Enviar calificación',
              icono: Icons.send_rounded,
              onPressed: _estrellas == 0 ? null : () => Navigator.pop(context, (estrellas: _estrellas, comentario: _comentario.text)),
            ),
          ],
        ),
      ),
    );
  }
}
