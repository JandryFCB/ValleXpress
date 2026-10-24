import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../config/theme.dart';
import '../../models/direccion.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/zoom_mapa.dart';

/// Lo que devuelve el selector al guardar
class DireccionElegida {
  const DireccionElegida({
    required this.tipo,
    required this.direccion,
    required this.latitud,
    required this.longitud,
    required this.esPredeterminada,
    this.nombre,
    this.referencia,
    this.instrucciones,
  });

  final TipoDireccion tipo;
  final String? nombre;
  final String direccion;
  final String? referencia;
  final String? instrucciones;
  final double latitud;
  final double longitud;
  final bool esPredeterminada;
}

/// Elegir (o editar) una dirección: el pin queda fijo al centro y se mueve el mapa por debajo, como en Uber.
/// Abajo van el tipo, la dirección escrita y los detalles para el repartidor.
class AddressPickerScreen extends StatefulWidget {
  const AddressPickerScreen({super.key, this.actual, this.paraLocal = false});

  /// true = se elige la ubicación del LOCAL de un negocio: sin tipos, sin "predeterminada" ni indicaciones
  final bool paraLocal;

  /// Dirección que se edita (null = dirección nueva)
  final Direccion? actual;

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  // Punto de partida si no hay ubicación del teléfono ni dirección guardada (zona de ValleXpress)
  static const LatLng _inicio = LatLng(-3.8320, -78.7590);

  final _mapa = MapController();
  late final ValueNotifier<LatLng> _centro;
  final _direccion = TextEditingController();
  final _nombre = TextEditingController();
  final _referencia = TextEditingController();
  final _instrucciones = TextEditingController();
  late TipoDireccion _tipo;
  late bool _predeterminada;
  bool _buscandoUbicacion = false;
  String? _errorDireccion;

  bool get _editando => widget.actual != null;

  @override
  void initState() {
    super.initState();
    final a = widget.actual;
    _centro = ValueNotifier(a != null ? LatLng(a.latitud, a.longitud) : _inicio);
    _tipo = a?.tipo ?? TipoDireccion.casa;
    _predeterminada = a?.esPredeterminada ?? false;
    _direccion.text = a?.direccion ?? '';
    _nombre.text = a?.nombre ?? '';
    _referencia.text = a?.referencia ?? '';
    _instrucciones.text = a?.instrucciones ?? '';
    // Dirección nueva: se intenta centrar en donde está la persona (sin molestar si no dio permiso todavía)
    if (!_editando) _centrarSiHayPermiso();
  }

  @override
  void dispose() {
    _mapa.dispose();
    _centro.dispose();
    for (final c in [_direccion, _nombre, _referencia, _instrucciones]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _centrarSiHayPermiso() async {
    try {
      final permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) await _irAMiUbicacion(silencioso: true);
    } catch (_) {
      // sin ubicación: se queda en el punto de partida
    }
  }

  Future<void> _irAMiUbicacion({bool silencioso = false}) async {
    if (_buscandoUbicacion) return;
    setState(() => _buscandoUbicacion = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silencioso && mounted) mostrarError(context, 'Activa la ubicación (GPS) de tu teléfono');
        return;
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied && !silencioso) permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        if (!silencioso && mounted) {
          mostrarError(
            context,
            permiso == LocationPermission.deniedForever
                ? 'El permiso de ubicación está bloqueado. Actívalo en los ajustes del teléfono.'
                : 'Necesitamos el permiso de ubicación para centrar el mapa donde estás.',
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      if (!mounted) return;
      final punto = LatLng(pos.latitude, pos.longitude);
      _centro.value = punto;
      _mapa.move(punto, 17);
    } catch (e) {
      if (!silencioso && mounted) mostrarError(context, 'No pudimos obtener tu ubicación. Mueve el mapa a mano.');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  void _guardar() {
    FocusScope.of(context).unfocus();
    final texto = _direccion.text.trim();
    if (texto.isEmpty) {
      setState(() => _errorDireccion = 'Escribe la dirección (calle, barrio o referencia)');
      return;
    }
    String? limpio(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(
      context,
      DireccionElegida(
        tipo: _tipo,
        nombre: limpio(_nombre),
        direccion: texto,
        referencia: limpio(_referencia),
        instrucciones: limpio(_instrucciones),
        latitud: _centro.value.latitude,
        longitud: _centro.value.longitude,
        esPredeterminada: _predeterminada,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    // Alto realmente disponible: sin el teclado. Así, al escribir, el formulario no se come el mapa entero.
    final alto = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;

    // ---------------------------- Mapa con el pin fijo al centro ----------------------------
    final mapa = Stack(
      children: [
        FlutterMap(
          mapController: _mapa,
          options: MapOptions(
            initialCenter: _centro.value,
            initialZoom: 16,
            minZoom: 5,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (camara, _) => _centro.value = camara.center,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ec.vallexpress.app',
              tileBuilder: oscuro ? darkModeTileBuilder : null,
            ),
            // OpenStreetMap exige mostrar el crédito en el mapa
            const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')], alignment: AttributionAlignment.bottomLeft),
          ],
        ),
        // El pin: su punta queda exactamente en el centro del mapa
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(
                Icons.location_on_rounded,
                size: 48,
                color: c.primario,
                shadows: const [Shadow(blurRadius: 10, color: Colors.black45)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BotonRedondo(icono: Icons.arrow_back_ios_new_rounded, tooltip: 'Atrás', onTap: () => Navigator.pop(context)),
                _BotonRedondo(icono: Icons.my_location_rounded, tooltip: 'Mi ubicación', cargando: _buscandoUbicacion, onTap: _irAMiUbicacion),
              ],
            ),
          ),
        ),
        Positioned(right: 12, bottom: 56, child: ZoomMapa(mapa: _mapa)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.tarjeta.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.borde),
              ),
              child: Text('Mueve el mapa para ubicar el pin', style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
        ),
      ],
    );

    // ---------------------------- Formulario ----------------------------
    final formulario = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.paraLocal ? 'Ubicación de tu negocio' : (_editando ? 'Editar dirección' : 'Nueva dirección'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 14),
        if (!widget.paraLocal)
          // En el celular se desliza de lado; en la tarjeta del computador bajan de línea (no se corta "Otro")
          esEscritorio(context)
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in TipoDireccion.values)
                      ChoiceChip(
                        avatar: Icon(t.icono, size: 18, color: _tipo == t ? Colors.white : c.textoSuave),
                        label: Text(t.etiqueta),
                        selected: _tipo == t,
                        showCheckmark: false,
                        labelStyle: TextStyle(color: _tipo == t ? Colors.white : c.texto, fontWeight: FontWeight.w600),
                        onSelected: (_) => setState(() => _tipo = t),
                      ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: [
                      for (final t in TipoDireccion.values)
                        ChoiceChip(
                          avatar: Icon(t.icono, size: 18, color: _tipo == t ? Colors.white : c.textoSuave),
                          label: Text(t.etiqueta),
                          selected: _tipo == t,
                          showCheckmark: false,
                          labelStyle: TextStyle(color: _tipo == t ? Colors.white : c.texto, fontWeight: FontWeight.w600),
                          onSelected: (_) => setState(() => _tipo = t),
                        ),
                    ],
                  ),
                ),
        const SizedBox(height: 16),
        CampoValle(
          controller: _direccion,
          etiqueta: 'Dirección',
          icono: Icons.signpost_outlined,
          mayusculas: TextCapitalization.sentences,
          maxLongitud: 500,
          maxLineas: 2,
          estado: _errorDireccion == null ? EstadoCampo.neutro : EstadoCampo.error,
          ayuda: _errorDireccion ?? 'Calle principal y secundaria, barrio o sector',
          onChanged: (_) {
            if (_errorDireccion != null) setState(() => _errorDireccion = null);
          },
        ),
        const SizedBox(height: 14),
        CampoValle(
          controller: _referencia,
          etiqueta: 'Referencia (opcional)',
          icono: Icons.flag_outlined,
          mayusculas: TextCapitalization.sentences,
          maxLongitud: 500,
          ayuda: 'Ej: frente al parque, portón verde',
        ),
        if (!widget.paraLocal)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Más detalles', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              children: [
                CampoValle(
                  controller: _nombre,
                  etiqueta: 'Nombre (opcional)',
                  icono: Icons.label_outline,
                  mayusculas: TextCapitalization.words,
                  maxLongitud: 50,
                  ayuda: 'Ej: Mi casa, Oficina',
                ),
                const SizedBox(height: 14),
                CampoValle(
                  controller: _instrucciones,
                  etiqueta: 'Indicaciones para el repartidor',
                  icono: Icons.delivery_dining_outlined,
                  mayusculas: TextCapitalization.sentences,
                  maxLongitud: 500,
                  maxLineas: 2,
                  ayuda: 'Ej: tocar el timbre dos veces',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        if (!widget.paraLocal)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar como predeterminada'),
            subtitle: const Text('Se propone primero cuando hagas un pedido'),
            value: _predeterminada,
            onChanged: (v) => setState(() => _predeterminada = v),
          ),
      ],
    );
    final guardar = BotonValle(
      texto: widget.paraLocal ? 'Guardar ubicación' : (_editando ? 'Guardar cambios' : 'Guardar dirección'),
      icono: Icons.check_rounded,
      onPressed: _guardar,
    );

    // Computador: el mapa grande a la izquierda y el formulario en una tarjeta a la derecha
    if (esEscritorio(context)) {
      return Scaffold(
        backgroundColor: c.fondo,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(margenWeb, 24, margenWeb, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.borde),
                  ),
                  child: mapa,
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 440,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.tarjeta,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: c.borde),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 12), child: formulario),
                      ),
                      Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: guardar),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(child: mapa),
          Container(
            constraints: BoxConstraints(maxHeight: alto * 0.5),
            decoration: BoxDecoration(
              color: c.fondo,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: c.borde)),
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: formulario,
              ),
            ),
          ),
          // Botón fijo abajo: siempre visible, sin tener que desplazarse
          Container(
            decoration: BoxDecoration(
              color: c.tarjeta,
              border: Border(top: BorderSide(color: c.borde)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: guardar),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón circular que flota sobre el mapa
class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({required this.icono, required this.onTap, required this.tooltip, this.cargando = false});

  final IconData icono;
  final VoidCallback onTap;
  final String tooltip;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Material(
      color: c.tarjeta,
      shape: CircleBorder(side: BorderSide(color: c.borde)),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 46,
            height: 46,
            child: cargando
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: c.primario),
                  )
                : Icon(icono, size: 20, color: c.texto),
          ),
        ),
      ),
    );
  }
}
