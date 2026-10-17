import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/admin.dart';
import '../../models/pedido.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../profile/perfil_screen.dart';
import 'aprobaciones_screen.dart';
import 'cobros_screen.dart';
import 'detalle_cifra_screen.dart';
import 'legal_admin_screen.dart';
import 'perfiles_screen.dart';
import 'tarifas_screen.dart';
import 'pedidos_admin_screen.dart';
import 'usuarios_admin_screen.dart';

/// Inicio del administrador: Resumen, Aprobaciones, Pedidos, Usuarios y Perfil.
/// Escucha el tiempo real: cada pedido nuevo o cambio de estado refresca las cifras.
class InicioAdminScreen extends StatefulWidget {
  const InicioAdminScreen({super.key});

  @override
  State<InicioAdminScreen> createState() => _InicioAdminScreenState();
}

class _InicioAdminScreenState extends State<InicioAdminScreen> {
  int _pestana = 0;
  int _pendientes = 0;

  @override
  void initState() {
    super.initState();
    TiempoReal.instancia.iniciar();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return AtrasEnPestanas(
      pestana: _pestana,
      irAPrimera: () => setState(() => _pestana = 0),
      child: Scaffold(
        body: PestanasAnimadas(
          indice: _pestana,
          children: [
            _Resumen(alPendientes: (n) => setState(() => _pendientes = n), irAAprobaciones: () => setState(() => _pestana = 1)),
            AprobacionesScreen(alCambiar: () => setState(() => _pendientes = (_pendientes - 1).clamp(0, 999))),
            const PedidosAdminScreen(),
            const UsuariosAdminScreen(),
            const PerfilScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _pestana,
          backgroundColor: c.tarjeta,
          indicatorColor: c.primario.withValues(alpha: 0.18),
          onDestinationSelected: (i) => setState(() => _pestana = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Resumen'),
            NavigationDestination(
              icon: Badge(isLabelVisible: _pendientes > 0, label: Text('$_pendientes'), child: const Icon(Icons.fact_check_outlined)),
              selectedIcon: const Icon(Icons.fact_check_rounded),
              label: 'Gestión',
            ),
            const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Pedidos'),
            const NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group_rounded), label: 'Usuarios'),
            const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}

// =============================================================================================
// Resumen
// =============================================================================================
class _Resumen extends StatefulWidget {
  const _Resumen({required this.alPendientes, required this.irAAprobaciones});

  final ValueChanged<int> alPendientes;
  final VoidCallback irAAprobaciones;

  @override
  State<_Resumen> createState() => _ResumenState();
}

class _ResumenState extends State<_Resumen> {
  ResumenAdmin? _r;
  String? _error;
  StreamSubscription? _vivo;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Muchos cambios seguidos (un pedido que avanza rápido) se agrupan en una sola recarga. Un comprobante nuevo
    // también recarga, para que aparezca arriba el aviso de pagos por revisar.
    _vivo = TiempoReal.instancia.cambios(tiposAviso: const {'comprobante_nuevo'}).listen((_) {
      _espera?.cancel();
      _espera = Timer(const Duration(milliseconds: 800), _cargar);
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await AdminService.resumen();
      if (!mounted) return;
      setState(() => (_r = r, _error = null));
      widget.alPendientes(r.pendientes);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _abrirCobros() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CobrosScreen()));
    _cargar();
  }

  Future<void> _abrirPerfiles() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilesScreen()));
    _cargar(); // pudo aprobar pendientes desde allí
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final nombre = (context.select<AuthProvider, String?>((a) => a.usuario?['nombre']?.toString()) ?? 'Admin').split(' ').first;
    return FondoValle(
      child: r == null
          ? (_error != null
                ? EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    color: AppTheme.errorColor,
                    titulo: 'No pudimos cargar el resumen',
                    mensaje: _error,
                    textoAccion: 'Reintentar',
                    onAccion: _cargar,
                  )
                : const EsqueletoLista(cantidad: 4, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _Saludo(nombre: nombre),
                  if (!r.correoConfigurado)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: TarjetaValle(
                        color: AppTheme.errorColor.withValues(alpha: 0.1),
                        colorBorde: AppTheme.errorColor.withValues(alpha: 0.5),
                        child: const Row(
                          children: [
                            Icon(Icons.mail_lock_rounded, color: AppTheme.errorColor),
                            SizedBox(width: 10),
                            Expanded(child: Text('Los correos no están saliendo: falta configurar BREVO_API_KEY y SMTP_FROM en el servidor')),
                          ],
                        ),
                      ),
                    ),
                  if (r.pendientes > 0)
                    Aparecer(
                      child: _AvisoPendientes(
                        icono: Icons.fact_check_rounded,
                        titulo: r.pendientes == 1 ? '1 cuenta espera tu revisión' : '${r.pendientes} cuentas esperan tu revisión',
                        detalle: 'Negocios y repartidores nuevos',
                        onTap: widget.irAAprobaciones,
                      ),
                    ),
                  if (r.comprobantesPorRevisar > 0)
                    Aparecer(
                      child: _AvisoPendientes(
                        icono: Icons.receipt_long_rounded,
                        color: AppTheme.infoColor,
                        titulo: r.comprobantesPorRevisar == 1 ? '1 comprobante de pago por revisar' : '${r.comprobantesPorRevisar} comprobantes de pago por revisar',
                        detalle: 'Comisiones que los negocios ya transfirieron',
                        onTap: _abrirCobros,
                      ),
                    ),
                  const SizedBox(height: 14),
                  _Cifras(r: r),
                  const EncabezadoSeccion('Ventas de la semana', subtitulo: 'Pedidos entregados en los últimos 7 días'),
                  Aparecer(
                    indice: 2,
                    child: TarjetaValle(child: _GraficaSemana(r: r)),
                  ),
                  if (r.enCurso.isNotEmpty) ...[const EncabezadoSeccion('Pedidos en curso ahora'), _EnCurso(enCurso: r.enCurso)],
                  if (r.mejores.isNotEmpty) ...[
                    const EncabezadoSeccion('Negocios que más venden', subtitulo: 'Últimos 30 días'),
                    Aparecer(indice: 3, child: _Mejores(mejores: r.mejores)),
                  ],
                  const EncabezadoSeccion('Comunidad'),
                  _Comunidad(r: r),
                  const EncabezadoSeccion('Configuración'),
                  _AccesoConfig(
                    icono: Icons.price_change_rounded,
                    titulo: 'Tarifas, comisión y zona',
                    detalle: 'Envío por distancia, lo que gana ValleXpress y dónde funciona',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TarifasScreen())),
                  ),
                  _AccesoConfig(
                    icono: Icons.savings_rounded,
                    titulo: 'Cobros a negocios',
                    detalle: 'Comisiones por cobrar cada semana y pagos recibidos',
                    insignia: r.comprobantesPorRevisar,
                    onTap: _abrirCobros,
                  ),
                  _AccesoConfig(
                    icono: Icons.gavel_rounded,
                    titulo: 'Términos y privacidad',
                    detalle: 'Versión vigente, quién la aceptó y enlaces para Google Play',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalAdminScreen())),
                  ),
                  _AccesoConfig(
                    icono: Icons.manage_accounts_rounded,
                    titulo: 'Perfiles y permisos',
                    detalle: 'Quién puede registrarse y quién necesita tu aprobación',
                    onTap: _abrirPerfiles,
                  ),
                ],
              ),
            ),
    );
  }
}

class _Saludo extends StatelessWidget {
  const _Saludo({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hola, $nombre 👋', style: tema.bodyLarge?.copyWith(color: c.textoSuave)),
              Text('Así va ValleXpress hoy', style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.admin_panel_settings_rounded, color: c.primario),
        ),
      ],
    );
  }
}

/// Tarjeta llamativa arriba del resumen para lo que espera una acción del administrador
class _AvisoPendientes extends StatelessWidget {
  const _AvisoPendientes({required this.icono, required this.titulo, required this.detalle, required this.onTap, this.color = AppTheme.warningColor});

  final IconData icono;
  final String titulo;
  final String detalle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TarjetaValle(
        onTap: onTap,
        color: color.withValues(alpha: 0.14),
        colorBorde: color.withValues(alpha: 0.6),
        child: Row(
          children: [
            IconoLatiendo(icono: icono, color: color, tamano: 40),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(detalle, style: tema.bodySmall),
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

/// Las cuatro cifras grandes del día
class _Cifras extends StatelessWidget {
  const _Cifras({required this.r});

  final ResumenAdmin r;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tarjetas = [
      _Cifra(
        icono: Icons.receipt_long_rounded,
        color: AppTheme.infoColor,
        tipo: 'pedidos',
        titulo: 'Pedidos hoy',
        valor: Text('${r.pedidosHoy}'),
        detalle: '${r.entregadosHoy} entregados',
      ),
      _Cifra(
        icono: Icons.payments_rounded,
        color: c.primario,
        tipo: 'ventas',
        titulo: 'Ventas hoy',
        valor: DineroAnimado(r.ventasHoy),
        detalle: 'Semana: ${Formato.dinero(r.ventasSemana)}',
      ),
      _Cifra(
        icono: Icons.account_balance_wallet_rounded,
        color: AppTheme.accentColor,
        tipo: 'ganancia',
        titulo: 'Ganancia ValleXpress',
        valor: DineroAnimado(r.comisionesHoy),
        // La comisión se gana al entregar; el cobro llega cuando el negocio paga su semana
        detalle: r.cobradoHoy > 0 ? 'Cobrado hoy: ${Formato.dinero(r.cobradoHoy)}' : 'Cobrado 7 días: ${Formato.dinero(r.cobradoSemana)}',
      ),
      _Cifra(
        icono: Icons.delivery_dining_rounded,
        color: AppTheme.repartidorColor,
        tipo: 'envios',
        titulo: 'Para repartidores',
        valor: DineroAnimado(r.enviosHoy),
        detalle: 'envíos de hoy',
      ),
      _Cifra(
        icono: Icons.local_fire_department_rounded,
        color: AppTheme.accentColor,
        tipo: 'encurso',
        titulo: 'En curso',
        valor: Text('${r.totalEnCurso}'),
        detalle: 'pedidos ahora mismo',
      ),
      _Cifra(
        icono: Icons.two_wheeler_rounded,
        color: AppTheme.successColor,
        tipo: 'enlinea',
        titulo: 'En línea',
        valor: Text('${r.repartidoresEnLinea}'),
        detalle: 'repartidores',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [for (final (i, t) in tarjetas.indexed) Aparecer(indice: i, child: t)],
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.tipo, required this.icono, required this.color, required this.titulo, required this.valor, required this.detalle});

  final String tipo; // qué detalle abre al tocarla
  final IconData icono;
  final Color color;
  final String titulo;
  final Widget valor;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return TarjetaValle(
      padding: const EdgeInsets.all(14),
      // Como en el banco: al tocar la cifra se ven sus movimientos
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetalleCifraScreen(tipo: tipo, titulo: titulo, icono: icono, color: color))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icono, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: tema.labelLarge?.copyWith(color: c.textoSuave),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.textoSuave),
            ],
          ),
          DefaultTextStyle.merge(
            style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            child: valor,
          ),
          Text(
            detalle,
            style: tema.bodySmall?.copyWith(color: c.textoSuave),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Barras de ventas por día: crecen desde abajo al cargar; la de hoy va resaltada
class _GraficaSemana extends StatelessWidget {
  const _GraficaSemana({required this.r});

  final ResumenAdmin r;

  static const _dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final maximo = r.semana.fold<double>(0, (m, d) => d.ventas > m ? d.ventas : m);
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in r.semana.indexed)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(d.ventas > 0 ? '\$${d.ventas.toStringAsFixed(0)}' : '', style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: maximo == 0 ? 0 : d.ventas / maximo),
                    duration: Duration(milliseconds: 500 + 70 * i),
                    curve: Curves.easeOutCubic,
                    builder: (_, f, _) => Container(
                      height: 6 + 104 * f,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: i == r.semana.length - 1
                              ? [c.primario, AppTheme.accentColor]
                              : [c.primario.withValues(alpha: 0.35), c.primario.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    i == r.semana.length - 1 ? 'Hoy' : _dias[d.dia.weekday - 1],
                    style: tema.labelMedium?.copyWith(fontWeight: i == r.semana.length - 1 ? FontWeight.w800 : FontWeight.w500),
                  ),
                  Text('${d.pedidos}', style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EnCurso extends StatelessWidget {
  const _EnCurso({required this.enCurso});

  final Map<String, int> enCurso;

  @override
  Widget build(BuildContext context) {
    final estados = EstadoPedido.values.where((e) => enCurso.containsKey(e.codigo));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final e in estados) InsigniaValle('${e.etiqueta}: ${enCurso[e.codigo]}', color: e.color, icono: e.icono)],
    );
  }
}

class _Mejores extends StatelessWidget {
  const _Mejores({required this.mejores});

  final List<({int id, String nombre, int pedidos, double ventas})> mejores;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    const medallas = ['🥇', '🥈', '🥉'];
    return TarjetaValle(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (i, m) in mejores.indexed)
            ListTile(
              leading: SizedBox(
                width: 32,
                child: Center(child: Text(i < 3 ? medallas[i] : '${i + 1}', style: tema.titleLarge)),
              ),
              title: Text(m.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(m.pedidos == 1 ? '1 pedido' : '${m.pedidos} pedidos'),
              trailing: Text(
                Formato.dinero(m.ventas),
                style: tema.titleSmall?.copyWith(color: c.primario, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

class _Comunidad extends StatelessWidget {
  const _Comunidad({required this.r});

  final ResumenAdmin r;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    Widget fila(IconData icono, String titulo, int total, String detalle) => ListTile(
      leading: Icon(icono, color: c.primario),
      title: Text(titulo),
      subtitle: detalle.isEmpty ? null : Text(detalle),
      trailing: Text('$total', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
    String porAprobacion(Map<String, int> m) => [
      if ((m['pendiente'] ?? 0) > 0) '${m['pendiente']} ${m['pendiente'] == 1 ? 'pendiente' : 'pendientes'}',
      if ((m['suspendido'] ?? 0) > 0) '${m['suspendido']} ${m['suspendido'] == 1 ? 'suspendido' : 'suspendidos'}',
      if ((m['rechazado'] ?? 0) > 0) '${m['rechazado']} ${m['rechazado'] == 1 ? 'rechazado' : 'rechazados'}',
    ].join(' · ');
    return TarjetaValle(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          fila(Icons.person_rounded, 'Clientes', r.usuarios['cliente'] ?? 0, ''),
          fila(Icons.storefront_rounded, 'Negocios', r.negocios.values.fold(0, (a, b) => a + b), porAprobacion(r.negocios)),
          fila(Icons.two_wheeler_rounded, 'Repartidores', r.repartidores.values.fold(0, (a, b) => a + b), porAprobacion(r.repartidores)),
          fila(Icons.groups_rounded, 'Cuentas en total', r.totalUsuarios, ''),
        ],
      ),
    );
  }
}

/// Una fila de la sección Configuración del resumen
class _AccesoConfig extends StatelessWidget {
  const _AccesoConfig({required this.icono, required this.titulo, required this.detalle, required this.onTap, this.insignia = 0});

  final int insignia; // cuántas cosas esperan revisión ahí dentro
  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TarjetaValle(
        onTap: onTap,
        child: Row(
          children: [
            Badge(isLabelVisible: insignia > 0, label: Text('$insignia'), child: Icon(icono, color: context.colores.primario)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(detalle, style: tema.bodySmall?.copyWith(color: context.colores.textoSuave)),
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
