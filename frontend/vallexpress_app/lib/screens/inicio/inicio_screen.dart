import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/legal.dart';
import '../../models/pedido.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carrito_provider.dart';
import '../../services/legal_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../widgets/ui/ui.dart';
import '../catalogo/negocio_detalle_screen.dart';
import '../legal/aceptar_legal_screen.dart';
import 'tutorial_screen.dart';
import '../catalogo/negocios_screen.dart';
import '../admin/inicio_admin_screen.dart';
import '../repartidor/inicio_repartidor_screen.dart';
import 'solo_app_screen.dart';
import '../vendedor/inicio_vendedor_screen.dart';
import '../pedidos/avisos_screen.dart';
import '../pedidos/carrito_screen.dart';
import '../pedidos/mis_pedidos_screen.dart';
import '../pedidos/pedido_detalle_screen.dart';
import '../profile/perfil_screen.dart';

/// Primera pantalla con sesión: cada rol tiene su inicio. Al entrar revisa si hay una versión nueva de los términos
/// o de la privacidad por aceptar: si la hay, la pide antes de dejar usar la app.
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  List<DocumentoLegal> _pendientes = const [];
  String? _revisadoPara;
  bool _tutorial = false; // primera vez con este perfil en el celular: tutorial de bienvenida

  // Una vez por usuario. Sin conexión no se bloquea: se vuelve a revisar en la próxima entrada.
  Future<void> _revisarLegal(String usuario, String rol) async {
    _revisadoPara = usuario;
    TutorialScreen.visto(rol).then((visto) {
      if (mounted && _revisadoPara == usuario && !visto) setState(() => _tutorial = true);
    });
    try {
      final p = await LegalService.pendientes();
      if (mounted && _revisadoPara == usuario) setState(() => _pendientes = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rol = context.select<AuthProvider, String>((a) => '${a.usuario?['tipoUsuario'] ?? 'cliente'}');
    final usuario = context.select<AuthProvider, String>((a) => '${a.usuario?['id'] ?? ''}');
    if (usuario.isNotEmpty && _revisadoPara != usuario) {
      _pendientes = const [];
      _tutorial = false;
      _revisarLegal(usuario, rol);
    }
    if (_pendientes.isNotEmpty) {
      return AceptarLegalScreen(key: ValueKey(usuario), pendientes: _pendientes, alAceptar: () => setState(() => _pendientes = const []));
    }
    if (_tutorial) return TutorialScreen(key: ValueKey('tutorial-$rol'), rol: rol, alTerminar: () => setState(() => _tutorial = false));
    return switch (rol) {
      'vendedor' => const InicioVendedorScreen(),
      // En la web no se reparte (sin GPS en segundo plano ni avisos del celular)
      'repartidor' => kIsWeb ? const SoloAppScreen() : const InicioRepartidorScreen(),
      'administrador' => const InicioAdminScreen(),
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
  static const _rutas = ['/inicio', '/pedidos', '/perfil'];
  int _pestana = PestanasAdaptables.indiceInicial(_rutas);
  int _noLeidos = 0;
  List<Pedido> _enCurso = [];
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    TiempoReal.instancia.iniciar();
    _subs.add(
      TiempoReal.instancia.avisos.listen((a) {
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        setState(() => _noLeidos++);
        mostrarMensaje(context, a.titulo, tipo: a.tipo == 'pedido_rechazado' ? TipoMensaje.error : TipoMensaje.info);
      }),
    );
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
    await abrirAvisos(context);
    _cargarNoLeidos();
  }

  // En el computador el carrito se abre dentro de la página (la barra de arriba sigue a la vista)
  void _abrirCarrito() => Navigator.push(contextoDeContenido(context), MaterialPageRoute(builder: (_) => const CarritoScreen()));

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CarritoProvider>();
    final escritorio = esEscritorio(context);

    return AtrasEnPestanas(
      pestana: _pestana,
      irAPrimera: () => setState(() => _pestana = 0),
      child: PestanasAdaptables(
        lateral: false,
        rutas: _rutas,
        indice: _pestana,
        onCambiar: (i) => setState(() => _pestana = i),
        paginas: [
          NegociosScreen(
            alRefrescar: _refrescar,
            // En el computador el saludo va en la bienvenida y los avisos y el carrito en la barra de arriba
            cabecera: escritorio
                ? (_enCurso.isEmpty ? null : _EnCursoEscritorio(enCurso: _enCurso))
                : _Cabecera(noLeidos: _noLeidos, enCurso: _enCurso, onAvisos: _abrirAvisos, onCarrito: _abrirCarrito, carrito: carrito),
          ),
          const MisPedidosScreen(conFlechaAtras: false),
          const PerfilScreen(),
        ],
        destinos: [
          const Destino(icono: Icons.storefront_outlined, iconoActivo: Icons.storefront_rounded, texto: 'Inicio'),
          Destino(icono: Icons.receipt_long_outlined, iconoActivo: Icons.receipt_long_rounded, texto: 'Pedidos', insignia: _enCurso.length),
          const Destino(icono: Icons.person_outline_rounded, iconoActivo: Icons.person_rounded, texto: 'Perfil'),
        ],
        accionesSuperiores: [
          IconButton(
            tooltip: 'Avisos',
            onPressed: _abrirAvisos,
            icon: Badge(
              isLabelVisible: _noLeidos > 0,
              label: Text(_noLeidos > 9 ? '9+' : '$_noLeidos'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 8),
          Rebote(
            valor: carrito.cantidadTotal,
            child: FilledButton.icon(
              onPressed: _abrirCarrito,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: const Color(0xFF15201A),
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              ),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: Text(carrito.vacio ? 'Carrito' : 'Carrito · ${carrito.cantidadTotal}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
        sobreLaBarra: BarraDeslizante(
          visible: _pestana == 0 && !carrito.vacio,
          child: BarraCarrito(key: const ValueKey('carrito'), carrito: carrito, onTap: _abrirCarrito),
        ),
      ),
    );
  }
}

/// En el computador: los pedidos en curso, en fila, debajo de la bienvenida
class _EnCursoEscritorio extends StatelessWidget {
  const _EnCursoEscritorio({required this.enCurso});

  final List<Pedido> enCurso;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tus pedidos en curso', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (var i = 0; i < enCurso.length; i++)
              Aparecer(key: ValueKey('en-curso-web-${enCurso[i].id}'), indice: i, child: _PedidoEnCurso(pedido: enCurso[i], ancho: 340)),
          ],
        ),
      ],
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
                    Text('¿Qué te llevamos hoy?', style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Comida, tiendas, farmacias, mascotas y más', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Avisos',
                onPressed: onAvisos,
                icon: Rebote(
                  valor: noLeidos,
                  child: Badge(
                    isLabelVisible: noLeidos > 0,
                    label: Text(noLeidos > 9 ? '9+' : '$noLeidos'),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Carrito',
                onPressed: onCarrito,
                icon: Rebote(
                  valor: carrito.cantidadTotal,
                  child: Badge(isLabelVisible: !carrito.vacio, label: Text('${carrito.cantidadTotal}'), child: const Icon(Icons.shopping_cart_outlined)),
                ),
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
                itemBuilder: (_, i) => Aparecer(
                  key: ValueKey('en-curso-${enCurso[i].id}'),
                  indice: i,
                  child: _PedidoEnCurso(pedido: enCurso[i], ancho: enCurso.length == 1 ? MediaQuery.of(context).size.width - 32 : 280),
                ),
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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PedidoDetalleScreen(pedidoId: pedido.id, inicial: pedido),
          ),
        ),
        child: Row(
          children: [
            // Late mientras el pedido está en marcha
            IconoLatiendo(icono: e.icono, color: e.color, activo: e != EstadoPedido.entregado, tamano: 40),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.etiqueta,
                    style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
