import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
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

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.pedidos.where((e) => e.pedidoId == widget.pedidoId).listen((_) {
      HapticFeedback.mediumImpact();
      _cargar();
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final p = await PedidosService.obtener(widget.pedidoId);
      if (!mounted) return;
      setState(() {
        _pedido = p;
        _error = null;
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
            const Text('El negocio aún no lo acepta, así que puedes cancelarlo sin problema.'),
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
    final r = await showModalBottomSheet<({int estrellas, String comentario})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaCalificar(negocio: _pedido!.negocioNombre),
    );
    if (r != null) await _accion(() => PedidosService.calificar(widget.pedidoId, puntuacion: r.estrellas, comentario: r.comentario), '¡Gracias por tu calificación!');
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
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _cargar, child: _contenido(p)),
    );
  }

  Widget? _barraAcciones(Pedido p) {
    final botones = <Widget>[
      if (p.puedeConfirmarRecibido)
        BotonValle(texto: 'Ya lo recibí', icono: Icons.check_circle_rounded, cargando: _ocupado, onPressed: () => _accion(() => PedidosService.confirmarRecibido(p.id), '¡Buen provecho!')),
      if (p.puedeCalificar) BotonValle(texto: 'Calificar a ${p.negocioNombre}', icono: Icons.star_rounded, tipo: p.puedeConfirmarRecibido ? TipoBoton.secundario : TipoBoton.principal, onPressed: _ocupado ? null : _calificar),
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
          Padding(
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

        // ---------------------------- Estado actual ----------------------------
        TarjetaValle(
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: e.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(e.icono, size: 40, color: e.color),
              ),
              const SizedBox(height: 12),
              Text(e.etiqueta, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(e == EstadoPedido.cancelado || e == EstadoPedido.rechazado ? (p.motivoCancelacion ?? e.descripcion) : e.descripcion,
                  textAlign: TextAlign.center, style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
              if (e.activo && e.paso < 5 && p.llegadaEstimada != null) ...[
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
              _Dato(Icons.payments_outlined, MetodoPago.nombre(p.metodoPago), p.pagado ? 'Pagado' : 'Se paga al recibir'),
              if (p.notas != null) ...[const SizedBox(height: 12), _Dato(Icons.chat_bubble_outline_rounded, 'Indicaciones', p.notas)],
              if (p.repartidor != null) ...[const SizedBox(height: 12), _Dato(Icons.two_wheeler_rounded, p.repartidor!.nombreCompleto, 'Tu repartidor')],
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
                        if (!ultimo) Expanded(child: Container(width: 2, color: i < actual ? c.primario : c.borde)),
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

/// Hoja para calificar al negocio: estrellas y un comentario opcional
class _HojaCalificar extends StatefulWidget {
  const _HojaCalificar({required this.negocio});

  final String negocio;

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
            Text('¿Qué tal estuvo ${widget.negocio}?', style: tema.titleLarge, textAlign: TextAlign.center),
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
