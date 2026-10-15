import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';
import '../models/pedido.dart';

/// Mapa de una entrega: el negocio, la dirección de entrega y el repartidor (que se desliza suave entre una
/// posición y la siguiente, en vez de saltar). Se encuadra solo para que se vean todos los puntos.
/// [haciaNegocio] dibuja la línea del repartidor al negocio (todavía no recoge) o a la entrega (ya lo lleva).
class MapaPedido extends StatefulWidget {
  const MapaPedido({super.key, this.negocio, this.entrega, this.repartidor, this.haciaNegocio = false, this.alto = 260, this.iconoRepartidor = Icons.two_wheeler_rounded});

  final Punto? negocio;
  final Punto? entrega;
  final Punto? repartidor;
  final bool haciaNegocio;
  final double alto;
  final IconData iconoRepartidor;

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

  @override
  void initState() {
    super.initState();
    _hasta = _ll(widget.repartidor);
    _anim.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant MapaPedido viejo) {
    super.didUpdateWidget(viejo);
    final nuevo = _ll(widget.repartidor);
    if (nuevo == null || nuevo == _hasta) return;
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.alto,
        child: Stack(
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
                  userAgentPackageName: 'com.example.vallexpress_app',
                  tileBuilder: oscuro ? darkModeTileBuilder : null,
                ),
                if (repartidor != null && destino != null)
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
              child: Material(
                color: c.tarjeta,
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(tooltip: 'Ver todo', icon: Icon(Icons.center_focus_strong_rounded, color: c.primario), onPressed: _encuadrar),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
