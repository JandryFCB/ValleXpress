import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/negocio.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import 'negocio_detalle_screen.dart';

/// Explorar negocios: buscador, categorías, "abiertos ahora" y la lista (se cargan más al llegar al final).
/// Con [cabecera] se usa como pestaña de inicio: sin barra de título y con la cabecera arriba del buscador.
class NegociosScreen extends StatefulWidget {
  const NegociosScreen({super.key, this.cabecera, this.alRefrescar});

  final Widget? cabecera;

  /// Se llama también al deslizar para refrescar (el inicio recarga sus pedidos en curso)
  final Future<void> Function()? alRefrescar;

  @override
  State<NegociosScreen> createState() => _NegociosScreenState();
}

class _NegociosScreenState extends State<NegociosScreen> {
  final _busqueda = TextEditingController();
  final _scroll = ScrollController();
  Timer? _espera;

  List<Categoria> _categorias = [];
  String? _categoria;
  bool _soloAbiertos = false;

  List<Negocio> _negocios = [];
  int _pagina = 1;
  bool _hayMas = false;
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _cargarMas();
    });
    CatalogoService.categorias().then((c) {
      if (mounted) setState(() => _categorias = c);
    }).catchError((_) {});
    _cargar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busqueda.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _pagina = 1;
    });
    try {
      final r = await CatalogoService.negocios(categoria: _categoria, busqueda: _busqueda.text, soloAbiertos: _soloAbiertos);
      if (!mounted) return;
      setState(() {
        _negocios = r.negocios;
        _hayMas = r.hayMas;
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
    if (!_hayMas || _cargandoMas || _cargando) return;
    setState(() => _cargandoMas = true);
    try {
      final r = await CatalogoService.negocios(categoria: _categoria, busqueda: _busqueda.text, soloAbiertos: _soloAbiertos, pagina: _pagina + 1);
      if (!mounted) return;
      setState(() {
        _negocios = [..._negocios, ...r.negocios];
        _pagina++;
        _hayMas = r.hayMas;
      });
    } catch (_) {
      // se reintenta al volver a llegar al final
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  void _alBuscar(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _cargar); // no se consulta en cada tecla
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return FondoValle(
      titulo: widget.cabecera == null ? 'Explorar' : null,
      child: RefreshIndicator(
        onRefresh: () => Future.wait([_cargar(), if (widget.alRefrescar != null) widget.alRefrescar!()]),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            if (widget.cabecera != null) SliverToBoxAdapter(child: widget.cabecera),
            // Buscador
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _busqueda,
                  textInputAction: TextInputAction.search,
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  onChanged: (v) {
                    setState(() {});
                    _alBuscar(v);
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar negocios o comidas',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Borrar búsqueda',
                            onPressed: () {
                              _busqueda.clear();
                              setState(() {});
                              _cargar();
                            },
                          ),
                  ),
                ),
              ),
            ),
            // Categorías y filtro de abiertos
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      avatar: Icon(Icons.access_time_rounded, size: 18, color: _soloAbiertos ? Colors.white : c.textoSuave),
                      label: const Text('Abiertos'),
                      selected: _soloAbiertos,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _soloAbiertos ? Colors.white : c.texto, fontWeight: FontWeight.w600),
                      onSelected: (v) {
                        setState(() => _soloAbiertos = v);
                        _cargar();
                      },
                    ),
                    const SizedBox(width: 8),
                    _chipCategoria(null, 'Todos', Icons.apps_rounded),
                    for (final cat in _categorias) _chipCategoria(cat.codigo, cat.descripcion, cat.icono),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ..._contenido(),
          ],
        ),
      ),
    );
  }

  Widget _chipCategoria(String? codigo, String texto, IconData icono) {
    final c = context.colores;
    final sel = _categoria == codigo;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icono, size: 18, color: sel ? Colors.white : c.textoSuave),
        label: Text(texto),
        selected: sel,
        showCheckmark: false,
        labelStyle: TextStyle(color: sel ? Colors.white : c.texto, fontWeight: FontWeight.w600),
        onSelected: (_) {
          setState(() => _categoria = codigo);
          _cargar();
        },
      ),
    );
  }

  List<Widget> _contenido() {
    if (_cargando) return const [SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))];
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar los negocios', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar),
        ),
      ];
    }
    if (_negocios.isEmpty) {
      final filtrando = _busqueda.text.isNotEmpty || _categoria != null || _soloAbiertos;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EstadoVacio(
            icono: Icons.storefront_outlined,
            titulo: filtrando ? 'Nada por aquí' : 'Aún no hay negocios',
            mensaje: filtrando ? 'Prueba con otra búsqueda o quita los filtros.' : 'Pronto habrá negocios de tu zona para pedir.',
            textoAccion: filtrando ? 'Quitar filtros' : null,
            onAccion: filtrando
                ? () {
                    _busqueda.clear();
                    setState(() {
                      _categoria = null;
                      _soloAbiertos = false;
                    });
                    _cargar();
                  }
                : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.separated(
          itemCount: _negocios.length + (_hayMas ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) {
            if (i == _negocios.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            final n = _negocios[i];
            return TarjetaNegocio(
              negocio: n,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus(); // al volver, el buscador no debe abrir el teclado
                Navigator.push(context, MaterialPageRoute(builder: (_) => NegocioDetalleScreen(negocio: n)));
              },
            );
          },
        ),
      ),
    ];
  }
}

/// Tarjeta de un negocio en la lista: portada, logo, nombre, categoría, calificación y datos de entrega
class TarjetaNegocio extends StatelessWidget {
  const TarjetaNegocio({super.key, required this.negocio, required this.onTap});

  final Negocio negocio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final n = negocio;
    return TarjetaValle(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            child: Stack(
              fit: StackFit.expand,
              children: [
                n.portada != null
                    ? ImagenRed(url: n.portada, radio: 0)
                    : Container(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [c.primario.withValues(alpha: 0.35), c.acento.withValues(alpha: 0.25)])),
                        child: Icon(n.categoria.icono, size: 56, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                if (!n.abiertoAhora) Container(color: Colors.black.withValues(alpha: 0.35)),
                Positioned(
                  top: 10,
                  right: 10,
                  child: InsigniaValle(
                    n.abiertoAhora ? 'Abierto' : 'Cerrado',
                    color: n.abiertoAhora ? AppTheme.successColor : Colors.white,
                    icono: n.abiertoAhora ? Icons.circle : Icons.nightlight_round,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                ImagenRed(url: n.logo, ancho: 52, alto: 52, radio: 14, icono: n.categoria.icono),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(n.categoria.descripcion, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                          if (n.numeroCalificaciones > 0) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded, size: 16, color: AppTheme.accentColor),
                            Text(' ${n.calificacion.toStringAsFixed(1)} (${n.numeroCalificaciones})', style: tema.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _Dato(Icons.timer_outlined, '${n.tiempoPreparacion} min'),
                          _Dato(Icons.delivery_dining_outlined, n.costoEnvio == 0 ? 'Envío gratis' : 'Envío ${Formato.dinero(n.costoEnvio)}'),
                          if (n.pedidoMinimo > 0) _Dato(Icons.shopping_bag_outlined, 'Mín. ${Formato.dinero(n.pedidoMinimo)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 15, color: c.textoSuave),
        const SizedBox(width: 4),
        Text(texto, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textoSuave)),
      ],
    );
  }
}
