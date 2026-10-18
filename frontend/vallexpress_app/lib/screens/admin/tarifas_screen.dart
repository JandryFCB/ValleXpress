import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';

/// Tarifas de ValleXpress: el envío por distancia (base + valor por km de ruta) y la comisión que se cobra a los
/// negocios. Un simulador muestra en vivo cuánto costaría un envío y cuánto recibe cada uno. Los pedidos ya hechos
/// no cambian: cada uno guardó las tarifas de su momento.
class TarifasScreen extends StatefulWidget {
  const TarifasScreen({super.key});

  @override
  State<TarifasScreen> createState() => _TarifasScreenState();
}

class _TarifasScreenState extends State<TarifasScreen> {
  final _base = TextEditingController();
  final _porKm = TextEditingController();
  final _factor = TextEditingController();
  final _comision = TextEditingController();
  // Zona de servicio
  final _zNombre = TextEditingController();
  final _zRadio = TextEditingController();
  final _zLat = TextEditingController();
  final _zLng = TextEditingController();
  bool _guardandoZona = false;
  Map<String, double>? _actuales;
  String? _error;
  bool _guardando = false;
  double _kmSimulados = 3; // distancia en línea recta del simulador

  @override
  void initState() {
    super.initState();
    for (final c in [_base, _porKm, _factor, _comision]) {
      c.addListener(() => setState(() {}));
    }
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_base, _porKm, _factor, _comision, _zNombre, _zRadio, _zLat, _zLng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait([AdminService.tarifas(), AdminService.zona()]);
      if (!mounted) return;
      _rellenar(r[0] as Map<String, double>);
      _rellenarZona(r[1]);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  void _rellenar(Map<String, double> t) {
    setState(() => (_actuales = t, _error = null));
    _base.text = t['envioBase']!.toStringAsFixed(2);
    _porKm.text = t['envioPorKm']!.toStringAsFixed(2);
    _factor.text = t['factorRuta']!.toString();
    _comision.text = t['comisionPorcentaje']!.toStringAsFixed(t['comisionPorcentaje']! % 1 == 0 ? 0 : 1);
  }

  void _rellenarZona(Map<String, dynamic> z) {
    _zNombre.text = '${z['nombre'] ?? ''}';
    _zRadio.text = '${z['radioKm'] ?? ''}';
    _zLat.text = '${z['latitud'] ?? ''}';
    _zLng.text = '${z['longitud'] ?? ''}';
  }

  Future<void> _guardarZona() async {
    final radio = _num(_zRadio), lat = _num(_zLat), lng = _num(_zLng);
    if (_zNombre.text.trim().length < 2 || radio == null || lat == null || lng == null) return mostrarError(context, 'Revisa los datos de la zona');
    setState(() => _guardandoZona = true);
    try {
      final z = await AdminService.guardarZona({'nombre': _zNombre.text.trim(), 'radioKm': radio, 'latitud': lat, 'longitud': lng});
      if (!mounted) return;
      _rellenarZona(z);
      mostrarExito(context, 'Zona guardada');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardandoZona = false);
    }
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Map<String, double> get _valores => {
        if (_num(_base) != null) 'envioBase': _num(_base)!,
        if (_num(_porKm) != null) 'envioPorKm': _num(_porKm)!,
        if (_num(_factor) != null) 'factorRuta': _num(_factor)!,
        if (_num(_comision) != null) 'comisionPorcentaje': _num(_comision)!,
      };

  bool get _hayCambios => _actuales != null && _valores.entries.any((e) => _actuales![e.key] != e.value);

  // Igual que el servidor (TarifasService): ruta = línea recta × factor; envío redondeado hacia arriba a 5 centavos
  double _envio(double kmLinea) {
    final v = _valores;
    final ruta = double.parse((kmLinea * (v['factorRuta'] ?? 1.3)).toStringAsFixed(2));
    final centavos = (((v['envioBase'] ?? 0) + (v['envioPorKm'] ?? 0) * ruta) * 100).round();
    return ((centavos + 4) ~/ 5) * 5 / 100;
  }

  Future<void> _guardar() async {
    final cambios = {for (final e in _valores.entries) if (_actuales![e.key] != e.value) e.key: e.value};
    setState(() => _guardando = true);
    try {
      final t = await AdminService.guardarTarifas(cambios);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      _rellenar(t);
      mostrarExito(context, 'Tarifas guardadas');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final teclado = const TextInputType.numberWithOptions(decimal: true);

    return FondoValle(
      appBar: AppBar(title: const Text('Tarifas, comisión y zona')),
      child: _actuales == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar las tarifas', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const EncabezadoSeccion('Envío', subtitulo: 'Lo paga el cliente y es 100 % del repartidor'),
                TarjetaValle(
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: CampoValle(controller: _base, etiqueta: 'Tarifa base \$', icono: Icons.flag_outlined, tipoTeclado: teclado, formateadores: decimal)),
                        const SizedBox(width: 12),
                        Expanded(child: CampoValle(controller: _porKm, etiqueta: 'Por km \$', icono: Icons.route_outlined, tipoTeclado: teclado, formateadores: decimal)),
                      ]),
                      const SizedBox(height: 12),
                      CampoValle(controller: _factor, etiqueta: 'Factor de ruta (1 a 3)', icono: Icons.alt_route_rounded, tipoTeclado: teclado, formateadores: decimal),
                      const SizedBox(height: 6),
                      Text(
                        'Las calles no van en línea recta: la distancia se multiplica por este factor (1.3 = 30 % más).',
                        style: tema.bodySmall?.copyWith(color: c.textoSuave),
                      ),
                    ],
                  ),
                ),
                const EncabezadoSeccion('Comisión de ValleXpress', subtitulo: 'Se descuenta al negocio de lo vendido en productos'),
                TarjetaValle(
                  child: CampoValle(controller: _comision, etiqueta: 'Comisión % (0 a 50)', icono: Icons.percent_rounded, tipoTeclado: teclado, formateadores: decimal),
                ),

                // Simulador
                const EncabezadoSeccion('Así quedaría', subtitulo: 'Mueve la distancia para ver el envío'),
                TarjetaValle(
                  color: c.primario.withValues(alpha: 0.08),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text('Cliente a ${_kmSimulados.toStringAsFixed(1)} km del local', style: tema.titleSmall)),
                        Text('Envío ${Formato.dinero(_envio(_kmSimulados))}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c.primario)),
                      ]),
                      Slider(value: _kmSimulados, min: 0.5, max: 10, divisions: 19, label: '${_kmSimulados.toStringAsFixed(1)} km', onChanged: (v) => setState(() => _kmSimulados = v)),
                      const Divider(),
                      Text('Pedido de \$20.00 en productos:', style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      _Linea('El cliente paga', 20 + _envio(_kmSimulados)),
                      _Linea('El negocio recibe', 20 - 20 * (_valores['comisionPorcentaje'] ?? 0) / 100),
                      _Linea('El repartidor gana', _envio(_kmSimulados)),
                      _Linea('ValleXpress gana', 20 * (_valores['comisionPorcentaje'] ?? 0) / 100, destacado: true),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                BotonValle(texto: 'Guardar tarifas', icono: Icons.check_rounded, cargando: _guardando, onPressed: _hayCambios ? _guardar : null),

                // Zona de servicio
                const EncabezadoSeccion('Zona de servicio', subtitulo: 'Fuera de este círculo no se pueden guardar direcciones ni locales'),
                TarjetaValle(
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(flex: 3, child: CampoValle(controller: _zNombre, etiqueta: 'Ciudad o zona', icono: Icons.location_city_rounded, maxLongitud: 60)),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: CampoValle(controller: _zRadio, etiqueta: 'Radio km', icono: Icons.radar_rounded, tipoTeclado: teclado, formateadores: decimal)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: CampoValle(controller: _zLat, etiqueta: 'Centro: latitud', icono: Icons.my_location_rounded, tipoTeclado: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                        const SizedBox(width: 12),
                        Expanded(child: CampoValle(controller: _zLng, etiqueta: 'Centro: longitud', icono: Icons.my_location_rounded, tipoTeclado: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                      ]),
                      const SizedBox(height: 6),
                      Text('Radio 0 = sin límite. Para crecer a otra ciudad, más adelante habrá varias zonas.', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                      const SizedBox(height: 12),
                      BotonValle(texto: 'Guardar zona', icono: Icons.check_rounded, tipo: TipoBoton.secundario, cargando: _guardandoZona, onPressed: _guardarZona),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.texto, this.monto, {this.destacado = false});

  final String texto;
  final double monto;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final estilo = destacado ? tema.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.accentColor) : tema.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(texto, style: estilo)), Text(Formato.dinero(monto), style: estilo)]),
    );
  }
}
