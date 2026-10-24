import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/producto.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../catalogo/negocio_detalle_screen.dart';
import 'producto_form_screen.dart';

/// Mis productos (vendedor): el menú agrupado por secciones, con acciones rápidas (agotado, ocultar, editar, borrar).
class MisProductosScreen extends StatefulWidget {
  const MisProductosScreen({super.key, this.alIrANegocio});

  /// Como pestaña de la web (sin flecha atrás): lleva a "Mi negocio" cuando aún no hay negocio
  final VoidCallback? alIrANegocio;

  @override
  State<MisProductosScreen> createState() => _MisProductosScreenState();
}

class _MisProductosScreenState extends State<MisProductosScreen> {
  bool _cargando = true;
  String? _error;
  bool _sinNegocio = false;
  Menu _menu = const Menu([], []);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _menu.productos.isEmpty;
      _error = null;
    });
    try {
      final m = await CatalogoService.misProductos();
      if (!mounted) return;
      setState(() {
        _menu = m;
        _cargando = false;
        _sinNegocio = false;
      });
    } catch (e) {
      if (!mounted) return;
      final texto = textoDeError(e);
      setState(() {
        _sinNegocio = texto.contains('no tienes un negocio');
        _error = _sinNegocio ? null : texto;
        _cargando = false;
      });
    }
  }

  List<String> get _secciones => _menu.secciones.whereType<String>().toList();

  Future<void> _abrirFormulario([Producto? p]) async {
    final cambio = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProductoFormScreen(producto: p, secciones: _secciones)));
    if (cambio == true && mounted) await _cargar();
  }

  Future<void> _estado(Producto p, EstadoProducto e) async {
    try {
      await CatalogoService.cambiarEstadoProducto(p.id, e);
      if (!mounted) return;
      mostrarMensaje(context, '"${p.nombre}": ${e.etiqueta.toLowerCase()}');
      await _cargar();
    } catch (err) {
      if (mounted) mostrarError(context, textoDeError(err));
    }
  }

  Future<void> _eliminar(Producto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar este producto?'),
        content: Text('"${p.nombre}" dejará de aparecer en tu menú. Los pedidos anteriores no se ven afectados.\n\nSi solo quieres quitarlo por un tiempo, mejor ocúltalo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CatalogoService.eliminarProducto(p.id);
      if (!mounted) return;
      mostrarMensaje(context, 'Producto eliminado');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (esEscritorio(context)) return _escritorio();
    return FondoValle(
      titulo: CatalogoService.gestionandoComoAdmin ? 'Productos' : 'Mis productos',
      botonFlotante: (_cargando || _error != null || _sinNegocio || _menu.productos.isEmpty)
          ? null
          : FloatingActionButton.extended(onPressed: () => _abrirFormulario(), icon: const Icon(Icons.add_rounded), label: const Text('Agregar')),
      child: _contenido(),
    );
  }

  String get _resumen {
    final total = _menu.productos.length;
    final ocultos = _menu.productos.where((p) => p.estado == EstadoProducto.oculto).length;
    final agotados = _menu.productos.where((p) => p.estado == EstadoProducto.agotado).length;
    return '$total producto${total == 1 ? '' : 's'}${agotados > 0 ? ' · $agotados agotado${agotados == 1 ? '' : 's'}' : ''}${ocultos > 0 ? ' · $ocultos oculto${ocultos == 1 ? '' : 's'}' : ''}';
  }

  // Computador: una tabla por sección (foto, producto, precio, estado, stock y acciones) a todo el ancho
  Widget _escritorio() {
    final lista = !_cargando && _error == null && !_sinNegocio && _menu.productos.isNotEmpty;
    return PaginaEscritorio(
      titulo: CatalogoService.gestionandoComoAdmin ? 'Productos' : 'Mis productos',
      subtitulo: lista ? _resumen : 'Tu menú: lo que ven los clientes',
      icono: Icons.restaurant_menu_rounded,
      conAtras: widget.alIrANegocio == null,
      desplazable: lista,
      acciones: [
        if (lista) FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), // el tema los pone a todo el ancho
          onPressed: () => _abrirFormulario(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar producto'),
        ),
      ],
      child: !lista
          ? _contenido()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entrada in _menu.porSeccion.entries) ...[
                  EncabezadoSeccion(entrada.key ?? 'Sin sección', subtitulo: '${entrada.value.length} producto${entrada.value.length == 1 ? '' : 's'}'),
                  _TablaProductos(
                    productos: entrada.value,
                    onEditar: _abrirFormulario,
                    onEstado: _estado,
                    onEliminar: _eliminar,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista();
    if (_sinNegocio) {
      return EstadoVacio(
        icono: Icons.storefront_outlined,
        titulo: 'Primero crea tu negocio',
        mensaje: 'Ve a "Mi negocio" para registrarlo; luego podrás cargar tus productos.',
        textoAccion: widget.alIrANegocio != null ? 'Ir a Mi negocio' : 'Volver',
        onAccion: widget.alIrANegocio ?? () => Navigator.pop(context),
      );
    }
    if (_error != null) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tus productos', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_menu.productos.isEmpty) {
      return EstadoVacio(
        icono: Icons.restaurant_menu_rounded,
        titulo: 'Tu menú está vacío',
        mensaje: 'Agrega tu primer producto con su foto y su precio.',
        textoAccion: 'Agregar producto',
        onAccion: () => _abrirFormulario(),
      );
    }

    final c = context.colores;
    final total = _menu.productos.length;
    final ocultos = _menu.productos.where((p) => p.estado == EstadoProducto.oculto).length;
    final agotados = _menu.productos.where((p) => p.estado == EstadoProducto.agotado).length;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Text(
            '$total producto${total == 1 ? '' : 's'}${agotados > 0 ? ' · $agotados agotado${agotados == 1 ? '' : 's'}' : ''}${ocultos > 0 ? ' · $ocultos oculto${ocultos == 1 ? '' : 's'}' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textoSuave),
          ),
          for (final entrada in _menu.porSeccion.entries) ...[
            EncabezadoSeccion(entrada.key ?? 'Sin sección'),
            for (final p in entrada.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TarjetaProducto(
                  producto: p,
                  onTap: () => _abrirFormulario(p),
                  extra: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            InsigniaValle(
                              p.estado.etiqueta,
                              icono: p.estado.icono,
                              color: switch (p.estado) {
                                EstadoProducto.disponible => AppTheme.successColor,
                                EstadoProducto.agotado => AppTheme.warningColor,
                                EstadoProducto.oculto => c.textoSuave,
                              },
                            ),
                            if (p.controlaStock) InsigniaValle('Stock: ${p.stock ?? 0}', color: AppTheme.infoColor, icono: Icons.inventory_2_outlined),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Opciones',
                        icon: Icon(Icons.more_horiz_rounded, color: c.textoSuave),
                        onSelected: (v) {
                          switch (v) {
                            case 'editar':
                              _abrirFormulario(p);
                            case 'disponible':
                              _estado(p, EstadoProducto.disponible);
                            case 'agotado':
                              _estado(p, EstadoProducto.agotado);
                            case 'oculto':
                              _estado(p, EstadoProducto.oculto);
                            case 'eliminar':
                              _eliminar(p);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'editar', child: Text('Editar')),
                          if (p.estado != EstadoProducto.disponible) const PopupMenuItem(value: 'disponible', child: Text('Marcar disponible')),
                          if (p.estado == EstadoProducto.disponible) const PopupMenuItem(value: 'agotado', child: Text('Marcar agotado')),
                          if (p.estado != EstadoProducto.oculto) const PopupMenuItem(value: 'oculto', child: Text('Ocultar del menú')),
                          PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: TextStyle(color: AppTheme.errorColor))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Tabla de productos de una sección (computador): encabezado y una fila por producto
class _TablaProductos extends StatelessWidget {
  const _TablaProductos({required this.productos, required this.onEditar, required this.onEstado, required this.onEliminar});

  final List<Producto> productos;
  final void Function(Producto) onEditar;
  final void Function(Producto, EstadoProducto) onEstado;
  final void Function(Producto) onEliminar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final cabecera = tema.labelMedium?.copyWith(color: c.textoSuave, fontWeight: FontWeight.w700);
    Widget fila(List<Widget> celdas) => Row(children: celdas);

    return TarjetaValle(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: fila([
              const SizedBox(width: 64),
              Expanded(flex: 5, child: Text('Producto', style: cabecera)),
              SizedBox(width: 110, child: Text('Precio', style: cabecera)),
              SizedBox(width: 170, child: Text('Estado', style: cabecera)),
              SizedBox(width: 110, child: Text('Stock', style: cabecera)),
              const SizedBox(width: 96),
            ]),
          ),
          for (final p in productos) ...[
            Divider(height: 1, color: c.borde),
            InkWell(
              onTap: () => onEditar(p),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: fila([
                  ImagenRed(url: p.miniatura ?? p.imagen, ancho: 48, alto: 48, radio: 12, icono: Icons.fastfood_outlined),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (p.descripcion != null)
                          Text(p.descripcion!, style: tema.bodySmall?.copyWith(color: c.textoSuave), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  SizedBox(width: 110, child: Text(Formato.dinero(p.precio), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  SizedBox(
                    width: 170,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // Tocar el estado lo cambia ahí mismo (disponible, agotado u oculto)
                      child: PopupMenuButton<EstadoProducto>(
                        tooltip: 'Cambiar estado',
                        onSelected: (e) => onEstado(p, e),
                        itemBuilder: (_) => [
                          for (final e in EstadoProducto.values)
                            PopupMenuItem(value: e, enabled: e != p.estado, child: Row(children: [Icon(e.icono, size: 18), const SizedBox(width: 10), Text(e.etiqueta)])),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InsigniaValle(p.estado.etiqueta, icono: p.estado.icono, color: _colorEstado(context, p.estado)),
                            Icon(Icons.arrow_drop_down_rounded, color: c.textoSuave),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(p.controlaStock ? '${p.stock ?? 0} u.' : '—', style: tema.bodyMedium?.copyWith(color: p.controlaStock ? c.texto : c.textoSuave)),
                  ),
                  SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(tooltip: 'Editar', onPressed: () => onEditar(p), icon: Icon(Icons.edit_outlined, color: c.textoSuave)),
                        IconButton(tooltip: 'Eliminar', onPressed: () => onEliminar(p), icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorColor)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _colorEstado(BuildContext context, EstadoProducto e) => switch (e) {
        EstadoProducto.disponible => AppTheme.successColor,
        EstadoProducto.agotado => AppTheme.warningColor,
        EstadoProducto.oculto => context.colores.textoSuave,
      };
}
