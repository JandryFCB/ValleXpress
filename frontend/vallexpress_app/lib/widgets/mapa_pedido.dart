import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';
import '../models/pedido.dart';
import '../services/rutas.dart';
import '../utils/contacto.dart';
import 'zoom_mapa.dart';

/// Mapa de una entrega: el negocio, la dirección de entrega y el repartidor (que se desliza suave entre una
/// posición y la siguiente, en vez de saltar). Se encuadra solo para que se vean todos los puntos.
/// [haciaNegocio]: el repartidor todavía va al negocio (la ruta pasa por el local) o ya lleva el pedido.
/// Dibuja la ruta por las calles (si el ruteador no responde, una línea recta). Se amplía a pantalla completa, que
/// sigue en vivo, y desde ahí se abre Google Maps con la mejor ruta. [soyRepartidor]: Google Maps sale desde donde
/// está el celular.
class MapaPedido extends StatefulWidget {
  const MapaPedido({
    super.key,
    this.negocio,
    this.entrega,
    this.repartidor,
    this.haciaNegocio = false,
    this.alto = 260,
    this.iconoRepartidor = Icons.two_wheeler_rounded,
    this.soyRepartidor = false,
    this.pantallaCompleta = false,
  });

  final Punto? negocio;
  final Punto? entrega;
  final Punto? repartidor;
  final bool haciaNegocio;
  final double alto;
  final IconData iconoRepartidor;
  final bool soyRepartidor;
  final bool pantallaCompleta;

  @override
  State<MapaPedido> createState() => _MapaPedidoState();
}

class _MapaPedidoState extends State<MapaPedido> with SingleTickerProviderStateMixin {
  final _mapa = MapController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  LatLng? _desde;
  LatLng? _hasta;
  DateTime? _ultimaPosicion;
  bool _listo = false;

  static LatLng? _ll(Punto? p) => p == null ? null : LatLng(p.latitud, p.longitud);

  /// Posición dibujada del repartidor (interpolada durante la animación). El avance es lineal: así la moto
  /// encadena un tramo con el siguiente sin frenar en cada posición.
  LatLng? get _repartidor {
    if (_hasta == null) return null;
    if (_desde == null) return _hasta;
    final t = _anim.value;
    return LatLng(_desde!.latitude + (_hasta!.latitude - _desde!.latitude) * t, _desde!.longitude + (_hasta!.longitude - _desde!.longitude) * t);
  }

  // La posición en vivo para la pantalla completa (que se abre aparte y debe seguir moviéndose)
  late final ValueNotifier<Punto?> _vivo = ValueNotifier(widget.repartidor);

  // Ruta por las calles. Se vuelve a pedir ("recalculando", como Google Maps) cuando el repartidor se sale de ella
  // más de 40 m, cuando cambia el tramo (recogió el pedido) o, por si acaso, cada 600 m. Nunca más de una cada 8 s.
  List<LatLng>? _ruta;
  String? _tramoRuta;
  LatLng? _origenRuta;
  DateTime? _ultimaRuta;
  bool _pidiendoRuta = false;
  static const _distancia = Distance();
  static const _fueraDeRutaM = 40.0;

  /// La ruta que falta: desde el repartidor (lo ya recorrido no se dibuja)
  List<LatLng>? _rutaRestante(LatLng? repartidor) {
    final ruta = _ruta;
    if (ruta == null || repartidor == null || ruta.length < 2) return ruta;
    final c = cercaniaARuta(ruta, repartidor);
    if (c.metros > _fueraDeRutaM) return ruta;      // se salió: se ve la ruta completa hasta que se recalcule
    return [repartidor, ...ruta.sublist(c.tramo + 1)];
  }

  List<LatLng> get _puntosRuta {
    final rep = _hasta;
    final negocio = _ll(widget.negocio);
    final entrega = _ll(widget.entrega);
    if (rep == null) return [negocio, entrega].whereType<LatLng>().toList();
    return [rep, if (widget.haciaNegocio) negocio, entrega].whereType<LatLng>().toList();
  }

  Future<void> _actualizarRuta() async {
    final puntos = _puntosRuta;
    if (puntos.length < 2 || _pidiendoRuta) return;
    final tramo = '${widget.haciaNegocio}|${puntos.skip(1).map((p) => '${p.latitude},${p.longitude}').join(';')}';
    if (_ruta != null && tramo == _tramoRuta && _origenRuta != null) {
      final fuera = _hasta != null && cercaniaARuta(_ruta!, puntos.first).metros > _fueraDeRutaM;
      final lejos = _distancia.as(LengthUnit.Meter, _origenRuta!, puntos.first) > 600;
      if (!fuera && !lejos) return;
      if (_ultimaRuta != null && DateTime.now().difference(_ultimaRuta!).inSeconds < 8) return;
    }
    _pidiendoRuta = true;
    _ultimaRuta = DateTime.now();
    final ruta = await Rutas.calcular(puntos);
    _pidiendoRuta = false;
    if (!mounted) return;
    setState(() {
      _ruta = ruta;
      _tramoRuta = tramo;
      _origenRuta = puntos.first;
    });
  }

  @override
  void initState() {
    super.initState();
    _hasta = _ll(widget.repartidor);
    _anim.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarRuta());
  }

  // Pantalla completa: el mismo mapa, que sigue la posición en vivo, con el botón de Google Maps
  void _ampliar() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Mapa del pedido')),
          body: ValueListenableBuilder<Punto?>(
            valueListenable: _vivo,
            builder: (_, posicion, _) => MapaPedido(
              negocio: widget.negocio,
              entrega: widget.entrega,
              repartidor: posicion,
              haciaNegocio: widget.haciaNegocio,
              iconoRepartidor: widget.iconoRepartidor,
              soyRepartidor: widget.soyRepartidor,
              pantallaCompleta: true,
            ),
          ),
        ),
      ),
    );
  }

  // Google Maps con la mejor ruta. El repartidor sale desde su celular; los demás ven el recorrido del repartidor
  // (o del local, si todavía no hay repartidor) hasta la entrega.
  void _abrirGoogleMaps() {
    final destino = widget.entrega ?? widget.negocio;
    if (destino == null) return;
    final pasaPorLocal = widget.haciaNegocio && widget.negocio != null && widget.entrega != null;
    abrirRutaEnMapas(
      context,
      origen: widget.soyRepartidor ? null : (widget.repartidor ?? (pasaPorLocal ? null : widget.negocio)),
      parada: pasaPorLocal && (widget.soyRepartidor || widget.repartidor != null) ? widget.negocio : null,
      destino: destino,
    );
  }

  @override
  void didUpdateWidget(covariant MapaPedido viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.haciaNegocio != widget.haciaNegocio) WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarRuta());
    _vivo.value = widget.repartidor;
    final nuevo = _ll(widget.repartidor);
    if (nuevo == null || nuevo == _hasta) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarRuta());
    final primeraVez = _hasta == null;
    _desde = _repartidor ?? nuevo;
    _hasta = nuevo;
    // El deslizamiento dura lo que tardó en llegar esta posición (el GPS manda cada ~3 s): cuando termina,
    // ya está por llegar la siguiente. Si hubo un corte largo, no se arrastra más de 4 s.
    final ahora = DateTime.now();
    final intervalo = _ultimaPosicion == null ? 900 : ahora.difference(_ultimaPosicion!).inMilliseconds.clamp(600, 4000);
    _ultimaPosicion = ahora;
    _anim.duration = Duration(milliseconds: intervalo);
    _anim.forward(from: 0);
    if (primeraVez) WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar());
  }

  @override
  void dispose() {
    _anim.dispose();
    _vivo.dispose();
    super.dispose();
  }

  List<LatLng> get _puntos => [_ll(widget.negocio), _ll(widget.entrega), _hasta].whereType<LatLng>().toList();

  CameraFit? get _encuadre {
    final p = _puntos;
    if (p.length < 2) return null;
    return CameraFit.bounds(bounds: LatLngBounds.fromPoints(p), padding: const EdgeInsets.fromLTRB(48, 56, 48, 48), maxZoom: 17);
  }

  void _encuadrar() {
    if (!_listo) return;
    final e = _encuadre;
    if (e != null) {
      _mapa.fitCamera(e);
    } else if (_puntos.isNotEmpty) {
      _mapa.move(_puntos.first, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final negocio = _ll(widget.negocio);
    final entrega = _ll(widget.entrega);
    final repartidor = _repartidor;
    final destino = widget.haciaNegocio ? negocio : entrega;
    final puntos = _puntos;
    final restante = _rutaRestante(repartidor);

    final mapa = Stack(
          children: [
            FlutterMap(
              mapController: _mapa,
              options: MapOptions(
                initialCenter: puntos.isEmpty ? const LatLng(-0.18, -78.48) : puntos.first,
                initialZoom: 15,
                initialCameraFit: _encuadre,
                onMapReady: () => _listo = true,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ec.vallexpress.app',
                  tileBuilder: oscuro ? darkModeTileBuilder : null,
                ),
                // Ruta por las calles; sin ella, la línea recta del repartidor a donde va
                if (restante != null)
                  PolylineLayer(polylines: [
                    Polyline(points: restante, color: Colors.white.withValues(alpha: 0.85), strokeWidth: 8),
                    Polyline(points: restante, color: repartidor == null ? AppTheme.accentColor : AppTheme.infoColor, strokeWidth: 5),
                  ])
                else if (repartidor != null && destino != null)
                  PolylineLayer(polylines: [Polyline(points: [repartidor, destino], color: AppTheme.infoColor.withValues(alpha: 0.7), strokeWidth: 4)]),
                MarkerLayer(
                  markers: [
                    if (negocio != null) Marker(point: negocio, width: 46, height: 46, child: const _Pin(icono: Icons.storefront_rounded, color: AppTheme.accentColor)),
                    if (entrega != null) Marker(point: entrega, width: 46, height: 46, child: const _Pin(icono: Icons.home_rounded, color: AppTheme.successColor)),
                    if (repartidor != null) Marker(point: repartidor, width: 58, height: 58, child: _PinRepartidor(icono: widget.iconoRepartidor)),
                  ],
                ),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')], alignment: AttributionAlignment.bottomLeft),
              ],
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Column(children: [
                _BotonMapa(tooltip: 'Ver todo', icono: Icons.center_focus_strong_rounded, onPressed: _encuadrar),
                if (!widget.pantallaCompleta) ...[
                  const SizedBox(height: 8),
                  _BotonMapa(tooltip: 'Ampliar', icono: Icons.open_in_full_rounded, onPressed: _ampliar),
                ],
                const SizedBox(height: 8),
                ZoomMapa(mapa: _mapa),
              ]),
            ),
            if (widget.pantallaCompleta && (widget.entrega ?? widget.negocio) != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: SafeArea(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: c.primario),
                    onPressed: _abrirGoogleMaps,
                    icon: const Icon(Icons.navigation_rounded),
                    label: Text(widget.soyRepartidor ? 'Navegar con Google Maps' : 'Ver la ruta en Google Maps'),
                  ),
                ),
              ),
          ],
        );
    if (widget.pantallaCompleta) return mapa;
    return ClipRRect(borderRadius: BorderRadius.circular(20), child: SizedBox(height: widget.alto, child: mapa));
  }
}

class _BotonMapa extends StatelessWidget {
  const _BotonMapa({required this.tooltip, required this.icono, required this.onPressed});

  final String tooltip;
  final IconData icono;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colores.tarjeta,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(tooltip: tooltip, icon: Icon(icono, color: context.colores.primario), onPressed: onPressed),
      );
}

/// Lo más cerca que pasa la ruta de un punto: distancia en metros y el tramo (índice) más cercano.
/// Proyección plana local: sobra para distancias de una ciudad.
@visibleForTesting
({double metros, int tramo}) cercaniaARuta(List<LatLng> ruta, LatLng p) {
  const mPorGrado = 111320.0;
  final kx = mPorGrado * cos(p.latitude * pi / 180);
  var mejor = double.infinity;
  var indice = 0;
  for (var i = 0; i < ruta.length - 1; i++) {
    final ax = (ruta[i].longitude - p.longitude) * kx, ay = (ruta[i].latitude - p.latitude) * mPorGrado;
    final bx = (ruta[i + 1].longitude - p.longitude) * kx, by = (ruta[i + 1].latitude - p.latitude) * mPorGrado;
    final dx = bx - ax, dy = by - ay;
    final largo = dx * dx + dy * dy;
    final t = largo == 0 ? 0.0 : (-(ax * dx + ay * dy) / largo).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = sqrt(cx * cx + cy * cy);
    if (d < mejor) {
      mejor = d;
      indice = i;
    }
  }
  return (metros: mejor, tramo: indice);
}


class _Pin extends StatelessWidget {
  const _Pin({required this.icono, required this.color});

  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Icon(icono, color: Colors.white, size: 22),
      );
}

/// El repartidor: círculo azul con un halo que late
class _PinRepartidor extends StatefulWidget {
  const _PinRepartidor({required this.icono});

  final IconData icono;

  @override
  State<_PinRepartidor> createState() => _PinRepartidorState();
}

class _PinRepartidorState extends State<_PinRepartidor> with SingleTickerProviderStateMixin {
  late final AnimationController _latido = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _latido,
      builder: (_, hijo) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30 + 28 * _latido.value,
            height: 30 + 28 * _latido.value,
            decoration: BoxDecoration(color: AppTheme.infoColor.withValues(alpha: 0.35 * (1 - _latido.value)), shape: BoxShape.circle),
          ),
          hijo!,
        ],
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.infoColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Icon(widget.icono, color: Colors.white, size: 22),
      ),
    );
  }
}
