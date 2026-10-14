import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/negocio.dart';
import '../../models/producto.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';

/// Detalle de un negocio y su menú agrupado por secciones. Recibe el negocio de la lista (se muestra al instante)
/// y luego carga el detalle completo y el menú.
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  void _verProducto(Producto p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetalleProducto(producto: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final n = _negocio;

    return Scaffold(
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
                      n.portada != null
                          ? ImagenRed(url: n.portada, radio: 0)
                          : Container(
                              decoration: BoxDecoration(gradient: LinearGradient(colors: [c.primario, c.primario.withValues(alpha: 0.5)])),
                              child: Icon(n.categoria.icono, size: 80, color: Colors.white.withValues(alpha: 0.7)),
                            ),
                      // degradado para que el título y la flecha se lean sobre cualquier foto
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.black54]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------------------------- Información del negocio ----------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TarjetaValle(
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
                                        InsigniaValle('${n.calificacion.toStringAsFixed(1)} (${n.numeroCalificaciones})', color: AppTheme.accentColor, icono: Icons.star_rounded),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (n.descripcion != null) ...[
                          const SizedBox(height: 12),
                          Text(n.descripcion!, style: tema.bodyMedium),
                        ],
                        const SizedBox(height: 14),
                        Divider(color: c.borde, height: 1),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            _Info(Icons.schedule_rounded, 'Hoy', n.horarioHoy?.texto ?? 'Sin horario'),
                            _Info(Icons.timer_outlined, 'Preparación', '${n.tiempoPreparacion} min'),
                            _Info(Icons.delivery_dining_outlined, 'Envío', n.costoEnvio == 0 ? 'Gratis' : Formato.dinero(n.costoEnvio)),
                            if (n.pedidoMinimo > 0) _Info(Icons.shopping_bag_outlined, 'Pedido mínimo', Formato.dinero(n.pedidoMinimo)),
                          ],
                        ),
                        if (n.local != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 18, color: c.textoSuave),
                              const SizedBox(width: 6),
                              Expanded(child: Text(n.local!.direccion, style: tema.bodySmall?.copyWith(color: c.textoSuave))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ---------------------------- Menú ----------------------------
              ..._menuSlivers(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _menuSlivers() {
    if (_cargando) return const [SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))];
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el menú', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar),
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
          sliver: SliverList.separated(
            itemCount: entrada.value.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => TarjetaProducto(producto: entrada.value[i], onTap: () => _verProducto(entrada.value[i])),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];
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
            Text(valor, style: tema.bodyMedium?.copyWith(color: c.texto, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}

/// Fila de un producto del menú: nombre, descripción, precio e imagen. Los agotados se ven atenuados.
class TarjetaProducto extends StatelessWidget {
  const TarjetaProducto({super.key, required this.producto, this.onTap, this.extra});

  final Producto producto;
  final VoidCallback? onTap;

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
                    Text(p.descripcion!, style: tema.bodySmall?.copyWith(color: c.textoSuave), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(Formato.dinero(p.precio), style: tema.titleMedium?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                      if (atenuado) ...[const SizedBox(width: 8), InsigniaValle('Agotado', color: c.textoSuave)],
                    ],
                  ),
                  if (extra != null) ...[const SizedBox(height: 8), extra!],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ImagenRed(url: p.miniatura ?? p.imagen, ancho: 88, alto: 88, radio: 14, icono: Icons.fastfood_outlined),
          ],
        ),
      ),
    );
  }
}

/// Hoja con el detalle de un producto
class _DetalleProducto extends StatelessWidget {
  const _DetalleProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = producto;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p.imagen != null) ...[
              AspectRatio(aspectRatio: 4 / 3, child: ImagenRed(url: p.imagen, radio: 20, icono: Icons.fastfood_outlined)),
              const SizedBox(height: 16),
            ],
            Text(p.nombre, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(Formato.dinero(p.precio), style: tema.titleLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
            if (p.descripcion != null) ...[const SizedBox(height: 12), Text(p.descripcion!, style: tema.bodyLarge)],
            const SizedBox(height: 16),
            if (!p.disponible)
              const InsigniaValle('Agotado por ahora', color: AppTheme.warningColor, icono: Icons.info_outline)
            else
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: c.textoSuave),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Muy pronto podrás agregarlo a tu carrito y pedirlo desde aquí.', style: tema.bodySmall?.copyWith(color: c.textoSuave))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
