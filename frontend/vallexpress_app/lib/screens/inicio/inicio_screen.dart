import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carrito_provider.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../widgets/ui/ui.dart';
import '../catalogo/negocio_detalle_screen.dart';
import '../catalogo/negocios_screen.dart';
import '../repartidor/inicio_repartidor_screen.dart';
import '../vendedor/inicio_vendedor_screen.dart';
import '../pedidos/avisos_screen.dart';
import '../pedidos/carrito_screen.dart';
import '../pedidos/mis_pedidos_screen.dart';
import '../pedidos/pedido_detalle_screen.dart';
import '../profile/perfil_screen.dart';

/// Primera pantalla con sesión: cada rol tiene su inicio.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rol = context.select<AuthProvider, String>((a) => '${a.usuario?['tipoUsuario'] ?? 'cliente'}');
    return switch (rol) {
      'vendedor' => const InicioVendedorScreen(),
      'repartidor' => const InicioRepartidorScreen(),
      _ => const InicioClienteScreen(),
    };
  }
}

/// Inicio del cliente: pestañas Inicio (negocios), Pedidos y Perfil. Mantiene la conexión en tiempo real: cuando
/// llega un aviso lo muestra arriba y sube el contador de la campana.
class InicioClienteScreen extends StatefulWidget {
  const InicioClienteScreen({super.key});

  @override
  State<InicioClienteScreen> createState() => _InicioClienteScreenState();
}

class _InicioClienteScreenState extends State<InicioClienteScreen> {
  int _pestana = 0;
  int _noLeidos = 0;
  List<Pedido> _enCurso = [];
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    TiempoReal.instancia.iniciar();
    _subs.add(TiempoReal.instancia.avisos.listen((a) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _noLeidos++);
      mostrarMensaje(context, a.titulo, tipo: a.tipo == 'pedido_rechazado' ? TipoMensaje.error : TipoMensaje.info);
    }));
    _subs.add(TiempoReal.instancia.cambios().listen((_) => _cargarEnCurso()));
    _refrescar();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _refrescar() => Future.wait([_cargarEnCurso(), _cargarNoLeidos()]);

  Future<void> _cargarEnCurso() async {
    try {
      final r = await PedidosService.misPedidos(estado: 'activos');
      if (mounted) setState(() => _enCurso = r.pedidos);
    } catch (_) {
      // sin conexión: se intenta de nuevo al refrescar
    }
  }

  Future<void> _cargarNoLeidos() async {
    try {
      final n = await PedidosService.avisosNoLeidos();
      if (mounted) setState(() => _noLeidos = n);
    } catch (_) {}
  }

  Future<void> _abrirAvisos() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AvisosScreen()));
    _cargarNoLeidos();
  }

  void _abrirCarrito() => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarritoScreen()));

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CarritoProvider>();
    final c = context.colores;

    return Scaffold(
      body: IndexedStack(
        index: _pestana,
        children: [
          NegociosScreen(
            alRefrescar: _refrescar,
            cabecera: _Cabecera(noLeidos: _noLeidos, enCurso: _enCurso, onAvisos: _abrirAvisos, onCarrito: _abrirCarrito, carrito: carrito),
          ),
          const MisPedidosScreen(conFlechaAtras: false),
          const PerfilScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pestana == 0 && !carrito.vacio) BarraCarrito(carrito: carrito, onTap: _abrirCarrito),
          NavigationBar(
            selectedIndex: _pestana,
            backgroundColor: c.tarjeta,
            indicatorColor: c.primario.withValues(alpha: 0.18),
            onDestinationSelected: (i) => setState(() => _pestana = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'Inicio'),
              NavigationDestination(
                icon: Badge(isLabelVisible: _enCurso.isNotEmpty, label: Text('${_enCurso.length}'), child: const Icon(Icons.receipt_long_outlined)),
                selectedIcon: const Icon(Icons.receipt_long_rounded),
                label: 'Pedidos',
              ),
              const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cabecera del inicio: saludo, campana de avisos, carrito y los pedidos en curso
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.noLeidos, required this.enCurso, required this.onAvisos, required this.onCarrito, required this.carrito});

  final int noLeidos;
  final List<Pedido> enCurso;
  final VoidCallback onAvisos;
  final VoidCallback onCarrito;
  final CarritoProvider carrito;

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final nombre = (context.select<AuthProvider, String?>((a) => a.usuario?['nombre']?.toString()) ?? '').split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_saludo()}${nombre.isEmpty ? '' : ', $nombre'} 👋', style: tema.bodyLarge?.copyWith(color: c.textoSuave)),
                    Text('¿Qué se te antoja hoy?', style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Avisos',
                onPressed: onAvisos,
                icon: Badge(isLabelVisible: noLeidos > 0, label: Text(noLeidos > 9 ? '9+' : '$noLeidos'), child: const Icon(Icons.notifications_none_rounded)),
              ),
              IconButton(
                tooltip: 'Carrito',
                onPressed: onCarrito,
                icon: Badge(isLabelVisible: !carrito.vacio, label: Text('${carrito.cantidadTotal}'), child: const Icon(Icons.shopping_cart_outlined)),
              ),
            ],
          ),
          if (enCurso.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 8),
                itemCount: enCurso.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _PedidoEnCurso(pedido: enCurso[i], ancho: enCurso.length == 1 ? MediaQuery.of(context).size.width - 32 : 280),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta compacta de un pedido en curso (arriba del inicio)
class _PedidoEnCurso extends StatelessWidget {
  const _PedidoEnCurso({required this.pedido, required this.ancho});

  final Pedido pedido;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final e = pedido.estado;
    return SizedBox(
      width: ancho,
      child: TarjetaValle(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: e.color.withValues(alpha: 0.14),
        colorBorde: e.color.withValues(alpha: 0.6),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(pedidoId: pedido.id, inicial: pedido))),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: e.color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(e.icono, color: e.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.etiqueta, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${pedido.negocioNombre} · #${pedido.id}', style: tema.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
