import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/contacto.dart';
import '../../utils/formato.dart';
import '../../widgets/mapa_pedido.dart';
import '../../widgets/ui/ui.dart';
import '../pedidos/pedido_detalle_screen.dart' show TarjetaRepartidor;
import 'pedidos_negocio_screen.dart';

/// Un pedido visto por el negocio: cliente, productos con sus notas (lo que necesita la cocina), entrega, pago,
/// los botones del siguiente paso y, cuando el repartidor va en camino, el mapa en vivo.
class PedidoNegocioScreen extends StatefulWidget {
  const PedidoNegocioScreen({super.key, required this.pedidoId, this.inicial});

  final int pedidoId;
  final Pedido? inicial;

  @override
  State<PedidoNegocioScreen> createState() => _PedidoNegocioScreenState();
}

class _PedidoNegocioScreenState extends State<PedidoNegocioScreen> {
  late Pedido? _pedido = widget.inicial;
  String? _error;
  Punto? _repartidorEn;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _cargar();
    _subs.add(TiempoReal.instancia.cambios(pedidoId: widget.pedidoId).listen((_) => _cargar()));
    _subs.add(TiempoReal.instancia.ubicaciones.where((u) => u.pedidoId == widget.pedidoId).listen((u) {
      if (mounted) setState(() => _repartidorEn = u.punto);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
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

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    final c = context.colores;
    return FondoValle(
      titulo: 'Pedido #${widget.pedidoId}',
      barraInferior: (p == null || !const {EstadoPedido.pendiente, EstadoPedido.confirmado, EstadoPedido.preparando, EstadoPedido.listo}.contains(p.estado))
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
                child: BotonesNegocio(pedido: p, alCambiar: _cargar),
              ),
            ),
      child: p == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el pedido', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(onRefresh: _cargar, child: _contenido(p)),
    );
  }

  Widget _contenido(Pedido p) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final e = p.estado;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Estado
        TarjetaValle(
          color: e.color.withValues(alpha: 0.1),
          colorBorde: e.color.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(e.icono, color: e.color, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e == EstadoPedido.pendiente ? 'Pedido nuevo' : e.etiqueta, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        if (p.fecha != null) 'Pedido ${Formato.hace(p.fecha!)}',
                        if (p.tiempoEstimado != null && e.activo) 'El cliente lo espera en ${p.tiempoEstimado} min',
                        if (e.fallido && p.motivoCancelacion != null) p.motivoCancelacion!,
                      ].join(' · '),
                      style: tema.bodySmall?.copyWith(color: c.textoSuave),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Productos (lo que necesita la cocina)
        const EncabezadoSeccion('Productos'),
        TarjetaValle(
          child: Column(
            children: [
              for (final l in p.productos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l.cantidad}×', style: tema.titleLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            if (l.notas != null) InsigniaValle(l.notas!, color: AppTheme.warningColor, icono: Icons.edit_note_rounded),
                          ],
                        ),
                      ),
                      Text(Formato.dinero(l.subtotal)),
                    ],
                  ),
                ),
              Divider(height: 1, color: c.borde),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: Text('Productos', style: tema.bodyMedium)), Text(Formato.dinero(p.subtotal))]),
              Row(children: [Expanded(child: Text('Envío (para el repartidor)', style: tema.bodyMedium)), Text(Formato.dinero(p.costoEnvio))]),
              const SizedBox(height: 4),
              Row(children: [Expanded(child: Text('Total que paga el cliente', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))), Text(Formato.dinero(p.total), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))]),
            ],
          ),
        ),
        if (p.notas != null) ...[
          const SizedBox(height: 12),
          TarjetaValle(
            color: AppTheme.warningColor.withValues(alpha: 0.1),
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.warningColor),
              const SizedBox(width: 10),
              Expanded(child: Text(p.notas!, style: tema.bodyMedium)),
            ]),
          ),
        ],

        // Cliente
        const EncabezadoSeccion('Cliente'),
        TarjetaValle(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_rounded, color: c.primario),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.cliente?.nombreCompleto ?? '', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  if (p.cliente?.telefono != null)
                    IconButton.filledTonal(tooltip: 'Llamar al cliente', onPressed: () => llamar(context, p.cliente!.telefono!), icon: const Icon(Icons.call_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined, color: c.textoSuave, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [p.direccionEntrega, if (p.referenciaEntrega != null) p.referenciaEntrega!, if (p.distanciaKm != null) 'a ${textoDistancia(p.distanciaKm!)} del local'].join(' · '),
                      style: tema.bodySmall?.copyWith(color: c.textoSuave),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.payments_outlined, color: c.textoSuave, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('${MetodoPago.nombre(p.metodoPago)} · ${p.pagado ? 'pagado' : 'se cobra al entregar'}', style: tema.bodySmall?.copyWith(color: c.textoSuave))),
              ]),
            ],
          ),
        ),

        // Repartidor y mapa
        if (p.repartidor != null) ...[
          const EncabezadoSeccion('Repartidor'),
          TarjetaRepartidor(repartidor: p.repartidor!, titulo: e == EstadoPedido.enCamino ? 'Viene a recoger el pedido' : 'Lleva el pedido'),
        ],
        if (p.enReparto) ...[
          const SizedBox(height: 12),
          MapaPedido(
            negocio: p.negocioLocal,
            entrega: p.entregaPunto,
            repartidor: _repartidorEn ?? p.repartidor?.ubicacion,
            haciaNegocio: e == EstadoPedido.enCamino,
            iconoRepartidor: p.repartidor?.vehiculo?.icono ?? Icons.two_wheeler_rounded,
          ),
        ],
        if (p.calificacion != null) ...[
          const EncabezadoSeccion('Calificación del cliente'),
          TarjetaValle(
            child: Row(children: [
              for (var i = 1; i <= 5; i++) Icon(i <= p.calificacion! ? Icons.star_rounded : Icons.star_border_rounded, color: AppTheme.accentColor),
              const SizedBox(width: 10),
              Expanded(child: Text(p.comentarioCalificacion ?? '', style: tema.bodySmall)),
            ]),
          ),
        ],
      ],
    );
  }
}
