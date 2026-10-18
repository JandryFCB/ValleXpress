import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../widgets/aviso_permisos.dart';
import '../../widgets/campana_avisos.dart';
import '../../widgets/ui/ui.dart';
import '../suscripcion/mi_suscripcion_screen.dart';
import 'pedido_negocio_screen.dart';

/// Pedidos que recibe el negocio: "En curso" (con los botones del siguiente paso) y "Anteriores".
/// Se actualiza sola con cada pedido nuevo o cambio de estado.
class PedidosNegocioScreen extends StatelessWidget {
  const PedidosNegocioScreen({super.key, this.conFlechaAtras = true});

  final bool conFlechaAtras;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: FondoValle(
        appBar: AppBar(
          title: const Text('Pedidos'),
          automaticallyImplyLeading: conFlechaAtras,
          actions: const [CampanaAvisos()],
          bottom: const TabBar(tabs: [Tab(text: 'En curso'), Tab(text: 'Anteriores')]),
        ),
        child: const Column(
          children: [
            AvisoPermisos(rol: 'vendedor', margen: EdgeInsets.fromLTRB(16, 12, 16, 0)),
            AvisoSuscripcion(),
            Expanded(child: TabBarView(children: [_Lista(estado: 'activos'), _Lista(estado: 'historial')])),
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatefulWidget {
  const _Lista({required this.estado});

  final String estado;

  @override
  State<_Lista> createState() => _ListaState();
}

class _ListaState extends State<_Lista> with AutomaticKeepAliveClientMixin {
  List<Pedido> _pedidos = [];
  bool _cargando = true;
  String? _error;
  StreamSubscription? _vivo;
  Timer? _reloj;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios().listen((_) => _cargar());
    // "hace 3 min" se actualiza solo
    _reloj = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _vivo?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await PedidosService.pedidosDelNegocio(estado: widget.estado);
      if (!mounted) return;
      setState(() {
        _pedidos = r.pedidos;
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const EsqueletoLista(cantidad: 4, conImagen: false);
    if (_error != null && _pedidos.isEmpty) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar los pedidos', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_pedidos.isEmpty) {
      final activos = widget.estado == 'activos';
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          SizedBox(
            height: 420,
            child: EstadoVacio(
              icono: activos ? Icons.storefront_outlined : Icons.receipt_long_outlined,
              titulo: activos ? 'Sin pedidos por ahora' : 'Aún no hay pedidos terminados',
              mensaje: activos ? 'Cuando un cliente te pida, aparecerá aquí al instante. Revisa que tu negocio esté abierto.' : 'Aquí verás los pedidos entregados, rechazados o cancelados.',
            ),
          ),
        ]),
      );
    }
    // Primero lo que necesita una acción del negocio
    final orden = [..._pedidos]..sort((a, b) => _prioridad(a).compareTo(_prioridad(b)));
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: orden.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => Aparecer(
          key: ValueKey('pedido-${orden[i].id}'),
          indice: i,
          child: TarjetaPedidoNegocio(
            pedido: orden[i],
            alCambiar: _cargar,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoNegocioScreen(pedidoId: orden[i].id, inicial: orden[i])));
              _cargar();
            },
          ),
        ),
      ),
    );
  }

  static int _prioridad(Pedido p) => switch (p.estado) {
        EstadoPedido.pendiente => 0,
        EstadoPedido.confirmado || EstadoPedido.preparando => 1,
        EstadoPedido.listo => 2,
        _ => 3,
      };
}

/// Tarjeta de un pedido para el negocio: cliente, productos, total y el botón del siguiente paso
class TarjetaPedidoNegocio extends StatelessWidget {
  const TarjetaPedidoNegocio({super.key, required this.pedido, required this.onTap, required this.alCambiar});

  final Pedido pedido;
  final VoidCallback onTap;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = pedido;
    final nuevo = p.estado == EstadoPedido.pendiente;
    return TarjetaValle(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      colorBorde: nuevo ? AppTheme.warningColor : (p.estado.activo ? p.estado.color.withValues(alpha: 0.5) : null),
      color: nuevo ? AppTheme.warningColor.withValues(alpha: 0.08) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${p.id}', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: Text(p.cliente?.nombreCompleto ?? '', style: tema.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(Formato.dinero(p.total), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(p.resumenProductos, maxLines: 3, overflow: TextOverflow.ellipsis, style: tema.bodyMedium?.copyWith(color: c.texto)),
          if (p.notas != null) ...[
            const SizedBox(height: 4),
            Text('“${p.notas}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: tema.bodySmall?.copyWith(color: c.textoSuave, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: InsigniaValle(_etiquetaNegocio(p), color: p.estado.color, icono: p.estado.icono))),
              const SizedBox(width: 8),
              if (p.fecha != null) Text(Formato.hace(p.fecha!), style: tema.labelSmall?.copyWith(color: c.textoSuave)),
            ],
          ),
          if (p.estado.activo) ...[
            const SizedBox(height: 12),
            BotonesNegocio(pedido: p, alCambiar: alCambiar),
          ],
        ],
      ),
    );
  }
}

/// Cómo ve el negocio cada estado
String _etiquetaNegocio(Pedido p) => switch (p.estado) {
      EstadoPedido.pendiente => '¡Nuevo! Por aceptar',
      EstadoPedido.listo => 'Listo · buscando repartidor',
      EstadoPedido.enCamino => '${p.repartidor?.nombre ?? 'Repartidor'} viene por él',
      EstadoPedido.recogido => 'En camino al cliente',
      EstadoPedido.entregado => 'Entregado',
      _ => p.estado.etiqueta,
    };

/// Botones del siguiente paso del negocio (aceptar/rechazar, preparando, listo). Los demás pasos son del repartidor.
class BotonesNegocio extends StatefulWidget {
  const BotonesNegocio({super.key, required this.pedido, required this.alCambiar});

  final Pedido pedido;
  final VoidCallback alCambiar;

  @override
  State<BotonesNegocio> createState() => _BotonesNegocioState();
}

class _BotonesNegocioState extends State<BotonesNegocio> {
  bool _ocupado = false;

  Future<void> _cambiar(String estado, {String? motivo, int? tiempo, required String exito}) async {
    setState(() => _ocupado = true);
    try {
      await PedidosService.cambiarEstadoNegocio(widget.pedido.id, estado, motivo: motivo, tiempoEstimado: tiempo);
      HapticFeedback.lightImpact();
      if (mounted) mostrarExito(context, exito);
      widget.alCambiar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _aceptar() async {
    final minutos = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿En cuánto llega el pedido #${widget.pedido.id}?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Contando la preparación y el envío. El cliente lo verá.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in const [20, 30, 40, 50, 60, 90])
                    ActionChip(label: Text('$m min'), onPressed: () => Navigator.pop(ctx, m)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (minutos != null) await _cambiar('confirmado', tiempo: minutos, exito: 'Pedido aceptado');
  }

  Future<void> _rechazar() async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿Por qué no puedes atenderlo?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Se lo diremos al cliente. Si pagaba con efectivo, no se le cobra nada.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              for (final m in const ['Se nos acabó un producto', 'Estamos muy llenos', 'Ya vamos a cerrar', 'No llegamos a esa dirección'])
                ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.chat_bubble_outline_rounded), title: Text(m), onTap: () => Navigator.pop(ctx, m)),
            ],
          ),
        ),
      ),
    );
    if (motivo != null) await _cambiar('rechazado', motivo: motivo, exito: 'Pedido rechazado');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final c = context.colores;
    switch (p.estado) {
      case EstadoPedido.pendiente:
        return Row(
          children: [
            Expanded(child: BotonValle(texto: 'Rechazar', tipo: TipoBoton.secundario, onPressed: _ocupado ? null : _rechazar)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: BotonValle(texto: 'Aceptar', icono: Icons.check_rounded, cargando: _ocupado, onPressed: _aceptar)),
          ],
        );
      case EstadoPedido.confirmado:
        return Row(
          children: [
            Expanded(child: BotonValle(texto: 'Preparando', tipo: TipoBoton.secundario, onPressed: _ocupado ? null : () => _cambiar('preparando', exito: 'Pedido en preparación'))),
            const SizedBox(width: 10),
            Expanded(child: BotonValle(texto: 'Listo', icono: Icons.inventory_2_rounded, cargando: _ocupado, onPressed: () => _cambiar('listo', exito: 'Avisamos a los repartidores'))),
          ],
        );
      case EstadoPedido.preparando:
        return BotonValle(texto: 'Está listo', icono: Icons.inventory_2_rounded, cargando: _ocupado, onPressed: () => _cambiar('listo', exito: 'Avisamos a los repartidores'));
      case EstadoPedido.listo:
        return Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.primario)),
          const SizedBox(width: 10),
          Expanded(child: Text('Esperando que un repartidor lo acepte…', style: Theme.of(context).textTheme.bodySmall)),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }
}
