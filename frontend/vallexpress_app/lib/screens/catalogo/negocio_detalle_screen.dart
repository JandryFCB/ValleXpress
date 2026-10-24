import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/negocio.dart';
import '../../models/producto.dart';
import '../../providers/carrito_provider.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../pedidos/carrito_screen.dart';

/// Detalle de un negocio y su menú agrupado por secciones. Recibe el negocio de la lista (se muestra al instante)
/// y luego carga el detalle completo y el menú. Desde aquí se agregan productos al carrito.
class NegocioDetalleScreen extends StatefulWidget {
  const NegocioDetalleScreen({super.key, required this.negocio});

  final Negocio negocio;

  @override
  State<NegocioDetalleScreen> createState() => _NegocioDetalleScreenState();
}

class _NegocioDetalleScreenState extends State<NegocioDetalleScreen> {
  late Negocio _negocio = widget.negocio;
  Menu? _menu;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _menu == null;
      _error = null;
    });
    try {
      final r = await Future.wait([CatalogoService.negocio(widget.negocio.id), CatalogoService.menu(widget.negocio.id)]);
      if (!mounted) return;
      setState(() {
        _negocio = r[0] as Negocio;
        _menu = r[1] as Menu;
        _cargando = false;
      });
      context.read<CarritoProvider>().actualizarNegocio(_negocio);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  /// El negocio recibe pedidos ahora (abierto, en horario y aceptando)
  bool get _recibePedidos => _negocio.abiertoAhora && _negocio.aceptaPedidos;

  void _verProducto(Producto p) {
    final detalle = _DetalleProducto(producto: p, recibePedidos: _recibePedidos, onAgregar: (cantidad, notas) => _agregar(p, cantidad, notas));
    if (esEscritorio(context)) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(padding: const EdgeInsets.only(top: 20), child: detalle),
          ),
        ),
      );
      return;
    }
    mostrarHoja(context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetalleProducto(producto: p, recibePedidos: _recibePedidos, onAgregar: (cantidad, notas) => _agregar(p, cantidad, notas)),
    );
  }

  Future<void> _agregar(Producto p, int cantidad, String? notas) async {
    final carrito = context.read<CarritoProvider>();
    if (carrito.esDeOtroNegocio(_negocio)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Empezar un carrito nuevo?'),
          content: Text('Tu carrito tiene productos de ${carrito.negocio!.nombre}. Un pedido es de un solo negocio: si sigues, se vaciará.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mantener')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vaciar y agregar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    carrito.agregar(_negocio, p, cantidad: cantidad, notas: notas);
    HapticFeedback.lightImpact();
    if (mounted) mostrarExito(context, cantidad == 1 ? 'Agregaste ${p.nombre} al carrito' : 'Agregaste $cantidad × ${p.nombre} al carrito');
  }

  @override
  Widget build(BuildContext context) {
    if (esEscritorio(context)) return _escritorio();
    final c = context.colores;
    final n = _negocio;
    final carrito = context.watch<CarritoProvider>();
    final miCarrito = !carrito.vacio && carrito.negocio?.id == n.id;

    return Scaffold(
      bottomNavigationBar: BarraDeslizante(
        visible: miCarrito,
        child: BarraCarrito(
          key: const ValueKey('carrito'),
          carrito: carrito,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarritoScreen())),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: c.degradadoFondo),
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 210,
                backgroundColor: c.fondo,
                foregroundColor: Colors.white,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'portada-negocio-${n.id}',
                        child: n.portada != null
                            ? ImagenRed(url: n.portada, radio: 0)
                            : Container(
                                decoration: BoxDecoration(gradient: LinearGradient(colors: [c.primario, c.primario.withValues(alpha: 0.5)])),
                                child: Icon(n.categoria.icono, size: 80, color: Colors.white.withValues(alpha: 0.7)),
                              ),
                      ),
                      // degradado para que el título y la flecha se lean sobre cualquier foto
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent, Colors.black54],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------------------------- Información del negocio ----------------------------
              SliverToBoxAdapter(
                child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: _info()),
              ),

              // ---------------------------- Menú ----------------------------
              ..._menuSlivers(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info() {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final n = _negocio;
    return TarjetaValle(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ImagenRed(url: n.logo, ancho: 64, alto: 64, radio: 16, icono: n.categoria.icono),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.nombre, style: tema.titleLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        InsigniaValle(n.abiertoAhora ? 'Abierto ahora' : 'Cerrado', color: n.abiertoAhora ? AppTheme.successColor : c.textoSuave),
                        InsigniaValle(n.categoria.descripcion, color: AppTheme.infoColor, icono: n.categoria.icono),
                        if (n.numeroCalificaciones > 0)
                          InsigniaValle(
                            '${n.calificacion.toStringAsFixed(1)} (${n.numeroCalificaciones})',
                            color: AppTheme.accentColor,
                            icono: Icons.star_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (n.descripcion != null) ...[const SizedBox(height: 12), Text(n.descripcion!, style: tema.bodyMedium)],
          const SizedBox(height: 14),
          Divider(color: c.borde, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _Info(Icons.schedule_rounded, 'Hoy', n.horarioHoy?.texto ?? 'Sin horario'),
              _Info(Icons.timer_outlined, 'Preparación', '${n.tiempoPreparacion} min'),
              _Info(
                Icons.delivery_dining_outlined,
                n.envioEstimado ? 'Envío a tu casa' : 'Envío desde',
                n.costoEnvio == 0 ? 'Gratis' : Formato.dinero(n.costoEnvio),
              ),
              if (n.pedidoMinimo > 0) _Info(Icons.shopping_bag_outlined, 'Pedido mínimo', Formato.dinero(n.pedidoMinimo)),
            ],
          ),
          if (n.local != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: c.textoSuave),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(n.local!.direccion, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                ),
              ],
            ),
          ],
          if (!_cargando && !_recibePedidos) ...[
            const SizedBox(height: 12),
            InsigniaValle(
              n.abiertoAhora ? 'No está recibiendo pedidos ahora' : 'Cerrado: puedes ver el menú, pero aún no pedir',
              color: AppTheme.warningColor,
              icono: Icons.info_outline,
            ),
          ],
        ],
      ),
    );
  }

  /// En el computador: portada, información y menú en dos columnas a la izquierda; el carrito fijo a la derecha
  Widget _escritorio() {
    final c = context.colores;
    final n = _negocio;
    return Scaffold(
      backgroundColor: c.fondo,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 24, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: SizedBox(
                            height: 240,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Hero(
                                  tag: 'portada-negocio-${n.id}',
                                  child: n.portada != null
                                      ? ImagenRed(url: n.portada, radio: 0)
                                      : Container(
                                          color: c.primario,
                                          child: Icon(n.categoria.icono, size: 96, color: Colors.white.withValues(alpha: 0.6)),
                                        ),
                                ),
                                Positioned(
                                  top: 16,
                                  left: 16,
                                  child: IconButton.filled(
                                    tooltip: 'Volver',
                                    style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF15201A)),
                                    onPressed: () => Navigator.maybePop(context),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 24, 8),
                      sliver: SliverToBoxAdapter(child: _info()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 24),
                      sliver: SliverMainAxisGroup(slivers: _menuSlivers(cuadricula: true)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 32, 24),
                child: SizedBox(width: 360, child: _CarritoLateral(negocio: n)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _menuSlivers({bool cuadricula = false}) {
    if (_cargando) return const [SliverFillRemaining(hasScrollBody: false, child: EsqueletoLista(cantidad: 4))];
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EstadoVacio(
            icono: Icons.cloud_off_rounded,
            color: AppTheme.errorColor,
            titulo: 'No pudimos cargar el menú',
            mensaje: _error,
            textoAccion: 'Reintentar',
            onAccion: _cargar,
          ),
        ),
      ];
    }
    final menu = _menu!;
    if (menu.productos.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EstadoVacio(icono: Icons.menu_book_outlined, titulo: 'Este negocio aún no tiene productos', mensaje: 'Vuelve pronto para ver su menú.'),
        ),
      ];
    }
    return [
      for (final entrada in menu.porSeccion.entries) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(entrada.key ?? 'Otros', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: cuadricula
              ? SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 460,
                    mainAxisExtent: 136,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: entrada.value.length,
                  itemBuilder: (_, i) => _producto(entrada.value[i], i),
                )
              : SliverList.separated(
                  itemCount: entrada.value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _producto(entrada.value[i], i),
                ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];
  }

  Widget _producto(Producto p, int i) {
    final carrito = context.watch<CarritoProvider>();
    return Aparecer(
      key: ValueKey('producto-${p.id}'),
      indice: i,
      child: TarjetaProducto(producto: p, enCarrito: carrito.negocio?.id == _negocio.id ? carrito.cantidadDe(p.id) : 0, onTap: () => _verProducto(p)),
    );
  }
}

/// En el computador, al lado del menú: lo que lleva el carrito, con cantidades editables, y el botón para seguir
class _CarritoLateral extends StatelessWidget {
  const _CarritoLateral({required this.negocio});

  final Negocio negocio;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final carrito = context.watch<CarritoProvider>();
    final otro = carrito.esDeOtroNegocio(negocio);
    void abrirCarrito() => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarritoScreen()));

    Widget fila(String texto, String valor, {bool fuerte = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(texto, style: fuerte ? tema.titleMedium?.copyWith(fontWeight: FontWeight.w800) : tema.bodyMedium),
          ),
          Text(
            valor,
            style: fuerte ? tema.titleMedium?.copyWith(fontWeight: FontWeight.w800) : tema.bodyMedium?.copyWith(color: c.texto),
          ),
        ],
      ),
    );

    return TarjetaValle(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag_rounded, color: c.primario),
              const SizedBox(width: 10),
              Text('Tu pedido', style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          if (carrito.vacio || otro) ...[
            Icon(Icons.add_shopping_cart_rounded, size: 48, color: c.textoSuave.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              otro ? 'Tu carrito tiene productos de ${carrito.negocio!.nombre}.' : 'Elige productos del menú y aparecerán aquí.',
              textAlign: TextAlign.center,
              style: tema.bodyMedium,
            ),
            if (otro) ...[const SizedBox(height: 12), OutlinedButton(onPressed: abrirCarrito, child: const Text('Ver ese carrito'))],
          ] else ...[
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: carrito.items.length,
                separatorBuilder: (_, __) => Divider(height: 20, color: c.borde),
                itemBuilder: (_, i) {
                  final it = carrito.items[i];
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.producto.nombre,
                              style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (it.notas != null)
                              Text(
                                it.notas!,
                                style: tema.bodySmall?.copyWith(color: c.textoSuave),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              Formato.dinero(it.subtotal),
                              style: tema.labelLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      SelectorCantidad(cantidad: it.cantidad, compacto: true, onCambiar: (v) => carrito.fijarCantidad(it.producto.id, v)),
                    ],
                  );
                },
              ),
            ),
            Divider(height: 28, color: c.borde),
            fila('Subtotal', Formato.dinero(carrito.subtotal)),
            fila(negocio.envioEstimado ? 'Envío' : 'Envío desde', carrito.costoEnvio == 0 ? 'Gratis' : Formato.dinero(carrito.costoEnvio)),
            fila('Total', Formato.dinero(carrito.total), fuerte: true),
            if (carrito.faltaParaMinimo > 0) ...[
              const SizedBox(height: 10),
              InsigniaValle(
                'Te faltan ${Formato.dinero(carrito.faltaParaMinimo)} para el pedido mínimo',
                color: AppTheme.warningColor,
                icono: Icons.info_outline,
              ),
            ],
            const SizedBox(height: 16),
            BotonValle(texto: 'Continuar con el pedido', icono: Icons.arrow_forward_rounded, onPressed: abrirCarrito),
          ],
        ],
      ),
    );
  }
}

/// Barra inferior con el resumen del carrito: "Ver carrito · 3 · $21.00"
class BarraCarrito extends StatelessWidget {
  const BarraCarrito({super.key, required this.carrito, required this.onTap});

  final CarritoProvider carrito;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Material(
          color: c.primario,
          borderRadius: BorderRadius.circular(18),
          elevation: 6,
          shadowColor: c.primario.withValues(alpha: 0.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // El contador rebota cada vez que se agrega algo
                  Rebote(
                    valor: carrito.cantidadTotal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        '${carrito.cantidadTotal}',
                        style: tema.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ver carrito',
                      style: tema.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  DineroAnimado(
                    carrito.subtotal,
                    estilo: tema.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icono, this.titulo, this.valor);

  final IconData icono;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 20, color: c.primario),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: tema.labelSmall?.copyWith(color: c.textoSuave)),
            Text(
              valor,
              style: tema.bodyMedium?.copyWith(color: c.texto, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fila de un producto del menú: nombre, descripción, precio e imagen. Los agotados se ven atenuados.
class TarjetaProducto extends StatelessWidget {
  const TarjetaProducto({super.key, required this.producto, this.onTap, this.extra, this.enCarrito = 0});

  final Producto producto;
  final VoidCallback? onTap;

  /// Unidades que ya están en el carrito (se muestra un contador sobre la imagen)
  final int enCarrito;

  /// Contenido adicional bajo el precio (el vendedor lo usa para el estado y el stock)
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = producto;
    final atenuado = !p.disponible && extra == null;

    return Opacity(
      opacity: atenuado ? 0.55 : 1,
      child: TarjetaValle(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (p.descripcion != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.descripcion!,
                      style: tema.bodySmall?.copyWith(color: c.textoSuave),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        Formato.dinero(p.precio),
                        style: tema.titleMedium?.copyWith(color: c.primario, fontWeight: FontWeight.w800),
                      ),
                      if (atenuado) ...[const SizedBox(width: 8), InsigniaValle('Agotado', color: c.textoSuave)],
                    ],
                  ),
                  if (extra != null) ...[const SizedBox(height: 8), extra!],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Stack(
              clipBehavior: Clip.none,
              children: [
                ImagenRed(url: p.miniatura ?? p.imagen, ancho: 88, alto: 88, radio: 14, icono: Icons.fastfood_outlined),
                if (enCarrito > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 26),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.primario,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.tarjeta, width: 2),
                      ),
                      child: Text(
                        '$enCarrito',
                        textAlign: TextAlign.center,
                        style: tema.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja con el detalle de un producto: cantidad, una nota ("sin cebolla") y el botón para agregarlo al carrito
class _DetalleProducto extends StatefulWidget {
  const _DetalleProducto({required this.producto, required this.recibePedidos, required this.onAgregar});

  final Producto producto;
  final bool recibePedidos;
  final void Function(int cantidad, String? notas) onAgregar;

  @override
  State<_DetalleProducto> createState() => _DetalleProductoState();
}

class _DetalleProductoState extends State<_DetalleProducto> {
  int _cantidad = 1;
  final _notas = TextEditingController();

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = widget.producto;
    final sePuede = p.disponible && widget.recibePedidos;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p.imagen != null) ...[
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ImagenRed(url: p.imagen, radio: 20, icono: Icons.fastfood_outlined),
              ),
              const SizedBox(height: 16),
            ],
            Text(p.nombre, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              Formato.dinero(p.precio),
              style: tema.titleLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800),
            ),
            if (p.descripcion != null) ...[const SizedBox(height: 12), Text(p.descripcion!, style: tema.bodyLarge)],
            const SizedBox(height: 16),
            if (!p.disponible)
              const InsigniaValle('Agotado por ahora', color: AppTheme.warningColor, icono: Icons.info_outline)
            else if (!widget.recibePedidos)
              const InsigniaValle('El negocio no está recibiendo pedidos ahora', color: AppTheme.warningColor, icono: Icons.info_outline)
            else ...[
              TextField(
                controller: _notas,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nota para el negocio (opcional)',
                  hintText: 'Ej: sin cebolla',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SelectorCantidad(cantidad: _cantidad, onCambiar: (v) => setState(() => _cantidad = v), minimo: 1),
                  const SizedBox(width: 16),
                  Expanded(
                    child: BotonValle(
                      texto: 'Agregar ${Formato.dinero(p.precio * _cantidad)}',
                      icono: Icons.add_shopping_cart_rounded,
                      onPressed: sePuede
                          ? () {
                              Navigator.pop(context);
                              widget.onAgregar(_cantidad, _notas.text);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Botones − cantidad + (en el detalle del producto y en el carrito)
class SelectorCantidad extends StatelessWidget {
  const SelectorCantidad({
    super.key,
    required this.cantidad,
    required this.onCambiar,
    this.minimo = 0,
    this.maximo = CarritoProvider.maxPorProducto,
    this.compacto = false,
  });

  final int cantidad;
  final ValueChanged<int> onCambiar;
  final int minimo;
  final int maximo;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tam = compacto ? 34.0 : 44.0;
    Widget boton(IconData icono, VoidCallback? accion, String ayuda) => SizedBox(
      width: tam,
      height: tam,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        iconSize: compacto ? 18 : 22,
        tooltip: ayuda,
        onPressed: accion == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                accion();
              },
        icon: Icon(icono),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.tarjeta,
        borderRadius: BorderRadius.circular(tam),
        border: Border.all(color: c.borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton(
            cantidad <= 1 && minimo == 0 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            cantidad > minimo ? () => onCambiar(cantidad - 1) : null,
            'Quitar uno',
          ),
          SizedBox(
            width: compacto ? 30 : 40,
            child: Text(
              '$cantidad',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          boton(Icons.add_rounded, cantidad < maximo ? () => onCambiar(cantidad + 1) : null, 'Agregar uno'),
        ],
      ),
    );
  }
}
