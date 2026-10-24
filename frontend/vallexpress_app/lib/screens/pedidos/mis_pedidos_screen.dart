import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import 'pedido_detalle_screen.dart';

/// Mis pedidos (cliente): "En curso" y "Anteriores". Se actualiza sola cuando cambia el estado de un pedido.
class MisPedidosScreen extends StatelessWidget {
  const MisPedidosScreen({super.key, this.conFlechaAtras = true});

  /// Falso cuando se muestra como pestaña del inicio
  final bool conFlechaAtras;

  @override
  Widget build(BuildContext context) {
    const listas = TabBarView(children: [_ListaPedidos(estado: 'activos'), _ListaPedidos(estado: 'historial')]);
    if (esEscritorio(context)) {
      return const DefaultTabController(
        length: 2,
        child: PaginaEscritorio(
          titulo: 'Mis pedidos',
          subtitulo: 'Sigue tus pedidos en vivo y revisa los anteriores',
          icono: Icons.receipt_long_rounded,
          desplazable: false,
          debajoDelTitulo: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'En curso'), Tab(text: 'Anteriores')]),
          child: listas,
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: FondoValle(
        appBar: AppBar(
          title: const Text('Mis pedidos'),
          automaticallyImplyLeading: conFlechaAtras,
          bottom: const TabBar(tabs: [Tab(text: 'En curso'), Tab(text: 'Anteriores')]),
        ),
        child: listas,
      ),
    );
  }
}

class _ListaPedidos extends StatefulWidget {
  const _ListaPedidos({required this.estado});

  final String estado;

  @override
  State<_ListaPedidos> createState() => _ListaPedidosState();
}

class _ListaPedidosState extends State<_ListaPedidos> with AutomaticKeepAliveClientMixin {
  List<Pedido> _pedidos = [];
  int _pagina = 1;
  bool _hayMas = false;
  bool _cargando = true;
  String? _error;
  StreamSubscription? _vivo;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios().listen((_) => _cargar());
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _cargarMas();
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await PedidosService.misPedidos(estado: widget.estado);
      if (!mounted) return;
      setState(() {
        _pedidos = r.pedidos;
        _hayMas = r.hayMas;
        _pagina = 1;
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

  Future<void> _cargarMas() async {
    if (!_hayMas || _cargando) return;
    _cargando = true;
    try {
      final r = await PedidosService.misPedidos(estado: widget.estado, pagina: _pagina + 1);
      if (!mounted) return;
      setState(() {
        _pedidos = [..._pedidos, ...r.pedidos];
        _hayMas = r.hayMas;
        _pagina++;
      });
    } catch (_) {
      // se reintenta al volver a llegar al final
    } finally {
      _cargando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando && _pedidos.isEmpty) return const EsqueletoLista();
    if (_error != null && _pedidos.isEmpty) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tus pedidos', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_pedidos.isEmpty) {
      final activos = widget.estado == 'activos';
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: EstadoVacio(
                icono: activos ? Icons.delivery_dining_outlined : Icons.receipt_long_outlined,
                titulo: activos ? 'No tienes pedidos en curso' : 'Aún no tienes pedidos anteriores',
                mensaje: activos ? 'Cuando hagas un pedido, aquí podrás seguirlo paso a paso.' : 'Aquí verás los pedidos que ya recibiste o se cancelaron.',
              ),
            ),
          ],
        ),
      );
    }
    Widget tarjeta(int i) => Aparecer(
          key: ValueKey('pedido-${_pedidos[i].id}'),
          indice: i % 12,
          child: TarjetaPedido(
            pedido: _pedidos[i],
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(pedidoId: _pedidos[i].id, inicial: _pedidos[i]), settings: RouteSettings(name: 'pedido/${_pedidos[i].id}')));
              _cargar();
            },
          ),
        );
    // Computador: en cuadrícula
    if (esEscritorio(context)) {
      return GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 20, bottom: 32),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 400, mainAxisExtent: 156, crossAxisSpacing: 16, mainAxisSpacing: 16),
        itemCount: _pedidos.length,
        itemBuilder: (_, i) => tarjeta(i),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _pedidos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => tarjeta(i),
      ),
    );
  }
}

/// Tarjeta de un pedido en la lista: negocio, estado, productos, total y fecha
class TarjetaPedido extends StatelessWidget {
  const TarjetaPedido({super.key, required this.pedido, required this.onTap});

  final Pedido pedido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = pedido;
    return TarjetaValle(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      colorBorde: p.estado.activo ? p.estado.color.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ImagenRed(url: p.negocioLogo, ancho: 44, alto: 44, radio: 12, icono: Icons.storefront_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.negocioNombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('#${p.id}${p.fecha == null ? '' : ' · ${Formato.fechaRelativa(p.fecha!)}'}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                  ],
                ),
              ),
              Text(Formato.dinero(p.total), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Text(p.resumenProductos, maxLines: 2, overflow: TextOverflow.ellipsis, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: InsigniaValle(p.estado.etiqueta, color: p.estado.color, icono: p.estado.icono))),
              if (p.puedeCalificar)
                Text('Califica', style: tema.labelLarge?.copyWith(color: AppTheme.accentColor))
              else if (p.calificacion != null)
                Row(children: [const Icon(Icons.star_rounded, size: 16, color: AppTheme.accentColor), Text(' ${p.calificacion}', style: tema.labelLarge)]),
              Icon(Icons.chevron_right_rounded, color: c.textoSuave),
            ],
          ),
        ],
      ),
    );
  }
}
