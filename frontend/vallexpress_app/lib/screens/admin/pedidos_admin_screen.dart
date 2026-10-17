import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../services/tiempo_real.dart';
import '../../utils/contacto.dart';
import '../../utils/formato.dart';
import '../../widgets/mapa_pedido.dart';
import '../../widgets/ui/ui.dart';
import '../pedidos/mis_pedidos_screen.dart';
import 'pedir_motivo.dart';

/// Todos los pedidos de la plataforma: en curso (se actualizan solos) e historial. Desde el detalle el
/// administrador ve a las tres partes (cliente, negocio, repartidor), las llama y puede cancelar una disputa.
class PedidosAdminScreen extends StatelessWidget {
  const PedidosAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: FondoValle(
        appBar: AppBar(
          title: const Text('Pedidos'),
          automaticallyImplyLeading: false,
          bottom: const TabBar(tabs: [Tab(text: 'En curso'), Tab(text: 'Historial'), Tab(text: 'Todos')]),
        ),
        child: const TabBarView(children: [_Lista(estado: 'activos'), _Lista(estado: 'historial'), _Lista(estado: null)]),
      ),
    );
  }
}

class _Lista extends StatefulWidget {
  const _Lista({required this.estado});

  final String? estado;

  @override
  State<_Lista> createState() => _ListaState();
}

class _ListaState extends State<_Lista> with AutomaticKeepAliveClientMixin {
  List<Pedido> _pedidos = [];
  bool _hayMas = false;
  int _pagina = 1;
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;
  StreamSubscription? _vivo;
  Timer? _espera;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios().listen((_) {
      _espera?.cancel();
      _espera = Timer(const Duration(milliseconds: 700), _cargar);
    });
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _cargarMas();
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    _espera?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await AdminService.pedidos(estado: widget.estado);
      if (mounted) setState(() => (_pedidos = r.items, _hayMas = r.hayMas, _pagina = 1, _cargando = false, _error = null));
    } catch (e) {
      if (mounted) setState(() => (_error = textoDeError(e), _cargando = false));
    }
  }

  Future<void> _cargarMas() async {
    if (!_hayMas || _cargandoMas) return;
    setState(() => _cargandoMas = true);
    try {
      final r = await AdminService.pedidos(estado: widget.estado, pagina: _pagina + 1);
      if (mounted) setState(() => (_pedidos = [..._pedidos, ...r.items], _hayMas = r.hayMas, _pagina = _pagina + 1));
    } catch (_) {
      // se reintenta al volver a llegar al final
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const EsqueletoLista();
    if (_error != null && _pedidos.isEmpty) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar los pedidos', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_pedidos.isEmpty) {
      return EstadoVacio(
        icono: Icons.receipt_long_outlined,
        titulo: widget.estado == 'activos' ? 'Nada en curso' : 'Sin pedidos',
        mensaje: widget.estado == 'activos' ? 'Cuando alguien haga un pedido aparecerá aquí al instante' : 'Todavía no hay pedidos aquí',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _pedidos.length + (_hayMas ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == _pedidos.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          final p = _pedidos[i];
          return Aparecer(
            key: ValueKey('p-${p.id}'),
            indice: i,
            child: TarjetaPedido(
              pedido: p,
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoAdminScreen(pedidoId: p.id, inicial: p)));
                if (mounted) _cargar();
              },
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================================
// Detalle de un pedido para el administrador
// =============================================================================================
class PedidoAdminScreen extends StatefulWidget {
  const PedidoAdminScreen({super.key, required this.pedidoId, this.inicial});

  final int pedidoId;
  final Pedido? inicial;

  @override
  State<PedidoAdminScreen> createState() => _PedidoAdminScreenState();
}

class _PedidoAdminScreenState extends State<PedidoAdminScreen> {
  late Pedido? _p = widget.inicial;
  String? _error;
  bool _cancelando = false;
  StreamSubscription? _vivo;

  // Los estados en los que el administrador todavía puede cancelar (igual que en el servidor)
  static const _cancelables = {
    EstadoPedido.pendiente, EstadoPedido.confirmado, EstadoPedido.preparando, EstadoPedido.listo, EstadoPedido.enCamino, EstadoPedido.recogido,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios(pedidoId: widget.pedidoId).listen((_) => _cargar());
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final p = await AdminService.pedido(widget.pedidoId);
      if (mounted) setState(() => (_p = p, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _cancelar() async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Cancelar el pedido #${widget.pedidoId}',
      explicacion: 'Les avisaremos al cliente, al negocio y al repartidor con este motivo. Los productos vuelven al stock.',
      textoBoton: 'Cancelar pedido',
      sugerencias: const ['El negocio no responde', 'El repartidor no llegó', 'Lo pidió el cliente', 'Dirección inválida', 'Pedido sospechoso'],
    );
    if (motivo == null) return;
    setState(() => _cancelando = true);
    try {
      final p = await AdminService.cancelarPedido(widget.pedidoId, motivo);
      if (!mounted) return;
      setState(() => _p = p);
      mostrarExito(context, 'Pedido cancelado. Ya les avisamos a todos');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return FondoValle(
      titulo: 'Pedido #${widget.pedidoId}',
      barraInferior: p != null && _cancelables.contains(p.estado)
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: BotonValle(texto: 'Cancelar pedido', icono: Icons.gavel_rounded, tipo: TipoBoton.peligro, cargando: _cancelando, onPressed: _cancelar),
              ),
            )
          : null,
      child: p == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el pedido', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(onRefresh: _cargar, child: _contenido(p)),
    );
  }

  Widget _contenido(Pedido p) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final e = p.estado;
    final pasos = p.lineaTiempo.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TarjetaValle(
          child: Column(
            children: [
              IconoLatiendo(icono: e.icono, color: e.color, activo: e.activo, tamano: 64),
              Text(e.etiqueta, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${p.negocioNombre} · ${p.fecha == null ? '' : Formato.fechaRelativa(p.fecha!)}', style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
              if (p.motivoCancelacion != null) ...[
                const SizedBox(height: 10),
                InsigniaValle(p.motivoCancelacion!, color: AppTheme.errorColor, icono: Icons.info_outline_rounded),
              ],
              const SizedBox(height: 14),
              DineroAnimado(p.total, estilo: tema.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: c.primario)),
              Text('${MetodoPago.nombre(p.metodoPago)} · ${p.pagado ? 'Pagado' : 'Se cobra al entregar'}', style: tema.bodySmall),
            ],
          ),
        ),

        const EncabezadoSeccion('Las tres partes'),
        TarjetaValle(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _Parte(icono: Icons.person_rounded, color: AppTheme.clienteColor, rol: 'Cliente', nombre: p.cliente?.nombreCompleto ?? '—', detalle: p.direccionEntrega, telefono: p.cliente?.telefono),
              _Parte(icono: Icons.storefront_rounded, color: AppTheme.vendedorColor, rol: 'Negocio', nombre: p.negocioNombre, detalle: p.negocioDireccion, telefono: p.negocioTelefono),
              _Parte(
                icono: p.repartidor?.vehiculo?.icono ?? Icons.two_wheeler_rounded,
                color: AppTheme.repartidorColor,
                rol: 'Repartidor',
                nombre: p.repartidor?.nombreCompleto ?? 'Sin asignar',
                detalle: p.repartidor?.descripcionVehiculo,
                telefono: p.repartidor?.telefono,
              ),
            ],
          ),
        ),

        if (p.enReparto) ...[
          const SizedBox(height: 12),
          MapaPedido(negocio: p.negocioLocal, entrega: p.entregaPunto, repartidor: p.repartidor?.ubicacion, haciaNegocio: e == EstadoPedido.enCamino, iconoRepartidor: p.repartidor?.vehiculo?.icono ?? Icons.two_wheeler_rounded),
        ],

        EncabezadoSeccion('Productos', subtitulo: p.cantidadProductos == 1 ? '1 unidad' : '${p.cantidadProductos} unidades'),
        TarjetaValle(
          child: Column(
            children: [
              for (final l in p.productos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Text('${l.cantidad}×', style: tema.labelLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.nombre, style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    Text(Formato.dinero(l.subtotal)),
                  ]),
                ),
              Divider(color: c.borde),
              _Monto('Productos', p.subtotal),
              _Monto(p.distanciaKm != null ? 'Envío (${p.distanciaKm!.toStringAsFixed(1)} km)' : 'Envío', p.costoEnvio),
              _Monto('Total', p.total, fuerte: true),
              if (p.comision != null) ...[
                Divider(color: c.borde),
                _Monto('Comisión ValleXpress (${(p.comisionPorcentaje ?? 0).toStringAsFixed(0)} %)', p.comision!),
                _Monto('Recibe el negocio', p.recibeNegocio ?? 0),
                _Monto('Gana el repartidor (envío)', p.costoEnvio),
              ],
            ],
          ),
        ),

        if (pasos.isNotEmpty) ...[
          const EncabezadoSeccion('Línea de tiempo'),
          TarjetaValle(
            child: Column(
              children: [
                for (final (i, paso) in pasos.indexed)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(children: [
                        Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: EstadoPedido.deCodigo(paso.key).color)),
                        if (i < pasos.length - 1) Container(width: 2, height: 28, color: c.borde),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(child: Text(EstadoPedido.deCodigo(paso.key).etiqueta, style: tema.bodyMedium)),
                      Text(Formato.hora(paso.value), style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                    ],
                  ),
              ],
            ),
          ),
        ],
        if (p.notas != null) ...[
          const EncabezadoSeccion('Indicaciones del cliente'),
          TarjetaValle(child: Text(p.notas!)),
        ],
      ],
    );
  }
}

class _Parte extends StatelessWidget {
  const _Parte({required this.icono, required this.color, required this.rol, required this.nombre, this.detalle, this.telefono});

  final IconData icono;
  final Color color;
  final String rol;
  final String nombre;
  final String? detalle;
  final String? telefono;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icono, color: color, size: 22),
      ),
      title: Text(nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text([rol, if (detalle != null && detalle!.isNotEmpty) detalle!].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: telefono == null ? null : IconButton.filledTonal(icon: const Icon(Icons.call_rounded), onPressed: () => llamar(context, telefono!)),
    );
  }
}

class _Monto extends StatelessWidget {
  const _Monto(this.texto, this.valor, {this.fuerte = false});

  final String texto;
  final double valor;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    final estilo = fuerte ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800) : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(texto, style: estilo)), Text(Formato.dinero(valor), style: estilo)]),
    );
  }
}
