import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../models/repartidor.dart';
import '../../services/api_error.dart';
import '../../services/gps_repartidor.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/contacto.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../pedidos/avisos_screen.dart';
import '../pedidos/mis_pedidos_screen.dart' show TarjetaPedido;
import '../profile/perfil_screen.dart';
import 'entrega_screen.dart';
import 'vehiculo_screen.dart';

/// Inicio del repartidor: pestañas Entregas, Historial y Perfil.
class InicioRepartidorScreen extends StatefulWidget {
  const InicioRepartidorScreen({super.key});

  @override
  State<InicioRepartidorScreen> createState() => _InicioRepartidorScreenState();
}

class _InicioRepartidorScreenState extends State<InicioRepartidorScreen> {
  int _pestana = 0;
  StreamSubscription? _avisos;

  @override
  void initState() {
    super.initState();
    TiempoReal.instancia.iniciar();
    _avisos = TiempoReal.instancia.avisos.listen((a) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      mostrarMensaje(context, a.titulo);
    });
  }

  @override
  void dispose() {
    _avisos?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Scaffold(
      body: IndexedStack(index: _pestana, children: const [_Entregas(), _Historial(), PerfilScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        backgroundColor: c.tarjeta,
        indicatorColor: c.primario.withValues(alpha: 0.18),
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.delivery_dining_outlined), selectedIcon: Icon(Icons.delivery_dining_rounded), label: 'Entregas'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}

// =============================================================================================
// Entregas: en línea, entrega en curso y pedidos libres
// =============================================================================================
class _Entregas extends StatefulWidget {
  const _Entregas();

  @override
  State<_Entregas> createState() => _EntregasState();
}

class _EntregasState extends State<_Entregas> {
  PerfilRepartidor? _perfil;
  bool _sinPerfil = false;
  PedidosLibres _libres = const PedidosLibres();
  Pedido? _enCurso;
  bool _cargando = true;
  bool _cambiandoLinea = false;
  int? _aceptando;
  String? _error;
  StreamSubscription? _vivo;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios().listen((_) => _cargar());
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final perfil = await PedidosService.miPerfilRepartidor();
      if (perfil == null) {
        if (mounted) setState(() => (_sinPerfil = true, _cargando = false));
        return;
      }
      final activos = await PedidosService.misEntregas(estado: 'activos');
      final enCurso = activos.pedidos.where((p) => p.enReparto).firstOrNull;
      final libres = perfil.aprobado && perfil.disponible ? await PedidosService.pedidosLibres() : const PedidosLibres();
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _sinPerfil = false;
        _enCurso = enCurso;
        _libres = libres;
        _error = null;
        _cargando = false;
      });
      _ajustarGps();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  // El GPS va encendido mientras está en línea o lleva un pedido
  Future<void> _ajustarGps() async {
    if ((_perfil?.disponible ?? false) || _enCurso != null) {
      final problema = await GpsRepartidor.instancia.iniciar();
      if (problema != null && mounted) mostrarError(context, problema);
    } else {
      GpsRepartidor.instancia.detener();
    }
  }

  Future<void> _cambiarLinea(bool enLinea) async {
    if (enLinea) {
      final problema = await GpsRepartidor.verificarPermiso();
      if (problema != null) return mounted ? mostrarError(context, problema) : null;
    }
    setState(() => _cambiandoLinea = true);
    try {
      await PedidosService.cambiarDisponibilidad(enLinea);
      HapticFeedback.mediumImpact();
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _cambiandoLinea = false);
    }
  }

  Future<void> _aceptar(Pedido p) async {
    setState(() => _aceptando = p.id);
    try {
      final pedido = await PedidosService.aceptarPedido(p.id);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedidoId: pedido.id, inicial: pedido)));
      _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
      _cargar();
    } finally {
      if (mounted) setState(() => _aceptando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(
      appBar: AppBar(
        title: const Text('Entregas'),
        automaticallyImplyLeading: false,
        actions: [IconButton(tooltip: 'Avisos', icon: const Icon(Icons.notifications_none_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AvisosScreen())))],
      ),
      child: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_sinPerfil) {
      return EstadoVacio(
        icono: Icons.two_wheeler_rounded,
        titulo: 'Registra tu vehículo',
        mensaje: 'Cuéntanos con qué repartes para empezar a recibir pedidos.',
        textoAccion: 'Registrar vehículo',
        onAccion: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const VehiculoScreen()));
          _cargar();
        },
      );
    }
    if (_error != null && _perfil == null) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tus entregas', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    final perfil = _perfil!;
    final c = context.colores;
    final tema = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // En línea
          TarjetaValle(
            color: perfil.disponible ? c.primario.withValues(alpha: 0.12) : null,
            colorBorde: perfil.disponible ? c.primario : null,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(perfil.disponible ? Icons.wifi_tethering_rounded : Icons.portable_wifi_off_rounded, color: perfil.disponible ? c.primario : c.textoSuave, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(perfil.disponible ? 'Estás en línea' : 'Estás fuera de línea', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text(perfil.disponible ? 'Te avisaremos cuando haya un pedido listo' : 'Conéctate para recibir pedidos', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                        ],
                      ),
                    ),
                    _cambiandoLinea
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Switch(value: perfil.disponible, onChanged: perfil.aprobado ? _cambiarLinea : null),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: c.borde),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Dato(Icons.check_circle_outline_rounded, '${perfil.numeroEntregas}', 'Entregas'),
                    _Dato(Icons.star_rounded, perfil.numeroCalificaciones == 0 ? '—' : perfil.calificacion.toStringAsFixed(1), 'Calificación'),
                    _Dato(perfil.vehiculo.icono, perfil.placa ?? perfil.vehiculo.etiqueta, 'Vehículo'),
                  ],
                ),
              ],
            ),
          ),
          if (!perfil.aprobado) ...[
            const SizedBox(height: 12),
            const InsigniaValle('Tu cuenta está en revisión: cuando la aprueben podrás conectarte', color: AppTheme.warningColor, icono: Icons.hourglass_top_rounded),
          ],

          // Entrega en curso
          if (_enCurso != null) ...[
            const EncabezadoSeccion('Entrega en curso'),
            TarjetaValle(
              colorBorde: AppTheme.infoColor,
              color: AppTheme.infoColor.withValues(alpha: 0.1),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedidoId: _enCurso!.id, inicial: _enCurso)));
                _cargar();
              },
              child: Row(
                children: [
                  Icon(_enCurso!.estado.icono, color: AppTheme.infoColor, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_enCurso!.estado == EstadoPedido.enCamino ? 'Ve a recoger a ${_enCurso!.negocioNombre}' : 'Lleva el pedido a ${_enCurso!.cliente?.nombre ?? 'tu cliente'}',
                            style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('#${_enCurso!.id} · ${_enCurso!.estado == EstadoPedido.enCamino ? _enCurso!.negocioDireccion ?? '' : _enCurso!.direccionEntrega}',
                            style: tema.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],

          // Pedidos libres
          if (perfil.disponible && _enCurso == null) ...[
            EncabezadoSeccion('Listos para recoger', subtitulo: _libres.listos.isEmpty ? 'Ahora no hay pedidos listos. Te avisamos al instante.' : null),
            for (final p in _libres.listos)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TarjetaLibre(pedido: p, aceptando: _aceptando == p.id, onAceptar: _aceptando == null ? () => _aceptar(p) : null),
              ),
            if (_libres.proximos.isNotEmpty) ...[
              const EncabezadoSeccion('Se están preparando', subtitulo: 'Podrás aceptarlos cuando el negocio los deje listos'),
              for (final p in _libres.proximos) Padding(padding: const EdgeInsets.only(bottom: 10), child: _TarjetaLibre(pedido: p)),
            ],
          ],
          if (!perfil.disponible && _enCurso == null && perfil.aprobado)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EstadoVacio(icono: Icons.nightlight_round, titulo: 'Descansando', mensaje: 'Activa "En línea" para ver los pedidos listos de tu zona.'),
            ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.valor, this.etiqueta);

  final IconData icono;
  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icono, size: 20, color: c.primario),
          const SizedBox(height: 4),
          Text(valor, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(etiqueta, style: tema.labelSmall?.copyWith(color: c.textoSuave)),
        ],
      ),
    );
  }
}

/// Un pedido libre: negocio, a qué distancia está, a dónde va, cuánto se gana y el botón para aceptarlo
class _TarjetaLibre extends StatelessWidget {
  const _TarjetaLibre({required this.pedido, this.onAceptar, this.aceptando = false});

  final Pedido pedido;
  final VoidCallback? onAceptar;
  final bool aceptando;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = pedido;
    final listo = p.estado == EstadoPedido.listo;
    return TarjetaValle(
      colorBorde: listo ? c.primario.withValues(alpha: 0.6) : null,
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
                    Text(p.negocioNombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text('#${p.id} · ${p.cantidadProductos} producto${p.cantidadProductos == 1 ? '' : 's'}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Formato.dinero(p.costoEnvio), style: tema.titleLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                  Text('ganas', style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              if (p.distanciaAlNegocioKm != null) _Etiqueta(Icons.storefront_outlined, 'Negocio a ${textoDistancia(p.distanciaAlNegocioKm!)}'),
              if (p.distanciaKm != null) _Etiqueta(Icons.route_outlined, 'Recorrido ${textoDistancia(p.distanciaKm!)}'),
              _Etiqueta(Icons.payments_outlined, p.metodoPago == 'efectivo' ? 'Cobrar ${Formato.dinero(p.total)}' : 'Ya pagado'),
            ],
          ),
          const SizedBox(height: 6),
          Text('Entrega: ${p.direccionEntrega}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
          if (listo) ...[
            const SizedBox(height: 12),
            BotonValle(texto: 'Aceptar pedido', icono: Icons.check_rounded, cargando: aceptando, onPressed: onAceptar),
          ],
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icono, size: 16, color: c.textoSuave),
      const SizedBox(width: 4),
      Text(texto, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// =============================================================================================
// Historial de entregas
// =============================================================================================
class _Historial extends StatefulWidget {
  const _Historial();

  @override
  State<_Historial> createState() => _HistorialState();
}

class _HistorialState extends State<_Historial> {
  List<Pedido> _pedidos = [];
  bool _cargando = true;
  StreamSubscription? _vivo;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios().listen((_) => _cargar());
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await PedidosService.misEntregas();
      if (mounted) setState(() => (_pedidos = r.pedidos.where((p) => !p.enReparto).toList(), _cargando = false));
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ganado = _pedidos.where((p) => p.estado == EstadoPedido.entregado || p.estado == EstadoPedido.recibido).fold(0.0, (s, p) => s + p.costoEnvio);
    return FondoValle(
      appBar: AppBar(title: const Text('Historial'), automaticallyImplyLeading: false),
      child: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: _pedidos.isEmpty
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                      SizedBox(height: 420, child: EstadoVacio(icono: Icons.history_rounded, titulo: 'Aún no tienes entregas', mensaje: 'Aquí verás cada pedido que entregues y lo que ganaste.')),
                    ])
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        TarjetaValle(
                          child: Row(children: [
                            Icon(Icons.savings_rounded, color: context.colores.primario, size: 30),
                            const SizedBox(width: 12),
                            Expanded(child: Text('Ganado en envíos', style: Theme.of(context).textTheme.titleSmall)),
                            Text(Formato.dinero(ganado), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: context.colores.primario)),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        for (final p in _pedidos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TarjetaPedido(
                              pedido: p,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedidoId: p.id, inicial: p))),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }
}
