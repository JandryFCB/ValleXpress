import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/gps_repartidor.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/contacto.dart';
import '../../utils/formato.dart';
import '../../widgets/mapa_pedido.dart';
import '../../widgets/ui/ui.dart';

/// La entrega en curso del repartidor: mapa con su posición, a dónde ir, cómo llegar, a quién llamar, cuánto
/// cobrar y el botón del siguiente paso (recogí -> entregué). Mientras está abierta, su GPS sigue enviando la ubicación.
class EntregaScreen extends StatefulWidget {
  const EntregaScreen({super.key, required this.pedidoId, this.inicial});

  final int pedidoId;
  final Pedido? inicial;

  @override
  State<EntregaScreen> createState() => _EntregaScreenState();
}

class _EntregaScreenState extends State<EntregaScreen> {
  late Pedido? _pedido = widget.inicial;
  Punto? _yo = GpsRepartidor.instancia.ultima;
  bool _ocupado = false;
  String? _error;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _cargar();
    GpsRepartidor.instancia.iniciar().then((problema) {
      if (problema != null && mounted) mostrarError(context, problema);
    });
    _subs.add(GpsRepartidor.instancia.posiciones.listen((p) => mounted ? setState(() => _yo = p) : null));
    _subs.add(TiempoReal.instancia.cambios(pedidoId: widget.pedidoId).listen((_) => _cargar()));
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

  Future<void> _paso(Future<Pedido> Function() fn, String exito) async {
    setState(() => _ocupado = true);
    try {
      final p = await fn();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _pedido = p);
      mostrarExito(context, exito);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _entregar(Pedido p) async {
    final cobrar = p.metodoPago == 'efectivo' && !p.pagado;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Entregaste el pedido?'),
        content: Text(cobrar ? 'Confirma que recibiste ${Formato.dinero(p.total)} en efectivo.' : 'Confirma que el cliente ya tiene su pedido.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Todavía no')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, entregado')),
        ],
      ),
    );
    if (ok == true) await _paso(() => PedidosService.marcarEntregado(p.id), '¡Entrega completada!');
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    return FondoValle(
      titulo: 'Entrega #${widget.pedidoId}',
      barraInferior: p == null ? null : _barra(p),
      child: p == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar la entrega', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(onRefresh: _cargar, child: _contenido(p)),
    );
  }

  Widget? _barra(Pedido p) {
    final c = context.colores;
    final boton = switch (p.estado) {
      EstadoPedido.enCamino => BotonValle(texto: 'Ya recogí el pedido', icono: Icons.inventory_2_rounded, cargando: _ocupado, onPressed: () => _paso(() => PedidosService.marcarRecogido(p.id), 'Ahora llévalo al cliente')),
      EstadoPedido.recogido => BotonValle(texto: 'Entregué el pedido', icono: Icons.where_to_vote_rounded, cargando: _ocupado, onPressed: () => _entregar(p)),
      _ => BotonValle(texto: 'Volver al inicio', icono: Icons.home_rounded, tipo: TipoBoton.secundario, onPressed: () => Navigator.pop(context)),
    };
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
        child: boton,
      ),
    );
  }

  Widget _contenido(Pedido p) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final recogiendo = p.estado == EstadoPedido.enCamino;
    final llevando = p.estado == EstadoPedido.recogido;
    final destino = recogiendo ? p.negocioLocal : p.entregaPunto;
    final cobrar = p.metodoPago == 'efectivo' && !p.pagado;

    if (!p.enReparto) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 40),
        EstadoVacio(
          icono: Icons.celebration_rounded,
          color: AppTheme.successColor,
          titulo: p.estado == EstadoPedido.entregado || p.estado == EstadoPedido.recibido ? '¡Entrega completada!' : 'Esta entrega terminó',
          mensaje: 'Ganaste ${Formato.dinero(p.costoEnvio)} por el envío.',
        ),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        MapaPedido(negocio: p.negocioLocal, entrega: p.entregaPunto, repartidor: _yo, haciaNegocio: recogiendo, alto: 300, soyRepartidor: true, iconoRepartidor: p.repartidor?.vehiculo?.icono ?? Icons.two_wheeler_rounded),
        const SizedBox(height: 12),

        // A dónde ir ahora
        TarjetaValle(
          colorBorde: c.primario,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(recogiendo ? '1. Recoge el pedido en' : '2. Llévalo a', style: tema.labelLarge?.copyWith(color: c.primario)),
              const SizedBox(height: 4),
              Text(recogiendo ? p.negocioNombre : (p.cliente?.nombreCompleto ?? 'Cliente'), style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(recogiendo ? (p.negocioDireccion ?? '') : p.direccionEntrega, style: tema.bodyMedium),
              if (llevando && p.referenciaEntrega != null) Text(p.referenciaEntrega!, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
              if (_yo != null && destino != null) ...[
                const SizedBox(height: 6),
                Text('Estás a ${textoDistancia(distanciaKm(_yo!, destino))}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (destino != null)
                    Expanded(child: BotonValle(texto: 'Cómo llegar', icono: Icons.navigation_rounded, tipo: TipoBoton.secundario, onPressed: () => abrirEnMapas(context, destino))),
                  if (destino != null) const SizedBox(width: 10),
                  Expanded(
                    child: BotonValle(
                      texto: recogiendo ? 'Llamar al local' : 'Llamar al cliente',
                      icono: Icons.call_rounded,
                      tipo: TipoBoton.secundario,
                      onPressed: () {
                        final tel = recogiendo ? p.negocioTelefono : p.cliente?.telefono;
                        if (tel == null) return mostrarError(context, 'No tenemos su teléfono');
                        llamar(context, tel);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (llevando && cobrar) ...[
          const SizedBox(height: 12),
          TarjetaValle(
            color: AppTheme.warningColor.withValues(alpha: 0.12),
            colorBorde: AppTheme.warningColor,
            child: Row(children: [
              const Icon(Icons.payments_rounded, color: AppTheme.warningColor, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Text('Cobra ${Formato.dinero(p.total)} en efectivo', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ]),
          ),
        ],
        if (p.notas != null) ...[
          const SizedBox(height: 12),
          TarjetaValle(child: Row(children: [
            Icon(Icons.chat_bubble_outline_rounded, color: c.primario),
            const SizedBox(width: 10),
            Expanded(child: Text(p.notas!, style: tema.bodyMedium)),
          ])),
        ],

        EncabezadoSeccion('Pedido de ${p.negocioNombre}', subtitulo: 'Ganas ${Formato.dinero(p.costoEnvio)} por este envío'),
        TarjetaValle(
          child: Column(children: [
            for (final l in p.productos)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Text('${l.cantidad}×', style: tema.titleSmall?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l.nombre)),
                ]),
              ),
            Divider(color: c.borde),
            Row(children: [Expanded(child: Text('Total del pedido', style: tema.titleSmall)), Text(Formato.dinero(p.total), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))]),
            Row(children: [Expanded(child: Text(MetodoPago.nombre(p.metodoPago), style: tema.bodySmall)), Text(p.pagado ? 'Pagado' : (cobrar ? 'Cobrar al entregar' : 'Por transferencia'), style: tema.bodySmall)]),
          ]),
        ),
      ],
    );
  }
}
