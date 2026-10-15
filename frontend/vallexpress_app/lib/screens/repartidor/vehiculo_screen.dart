import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../models/repartidor.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../widgets/ui/ui.dart';

/// Mi vehículo (repartidor): tipo, placa (si lleva) y color. Si aún no tiene perfil de repartidor, lo crea.
/// Devuelve el perfil guardado.
class VehiculoScreen extends StatefulWidget {
  const VehiculoScreen({super.key, this.actual});

  final PerfilRepartidor? actual;

  @override
  State<VehiculoScreen> createState() => _VehiculoScreenState();
}

class _VehiculoScreenState extends State<VehiculoScreen> {
  late Vehiculo _vehiculo = widget.actual?.vehiculo ?? Vehiculo.moto;
  late final _placa = TextEditingController(text: widget.actual?.placa ?? '');
  late final _color = TextEditingController(text: widget.actual?.color ?? '');
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _placa.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (_vehiculo.llevaPlaca && _placa.text.trim().isEmpty) return setState(() => _error = 'Escribe la placa de tu ${_vehiculo.etiqueta.toLowerCase()}');
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final perfil = await PedidosService.guardarVehiculo(vehiculo: _vehiculo, placa: _placa.text.trim(), color: _color.text.trim(), crear: widget.actual == null);
      if (!mounted) return;
      mostrarExito(context, 'Vehículo guardado');
      Navigator.pop(context, perfil);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return FondoValle(
      titulo: 'Mi vehículo',
      barraInferior: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: tema.bodySmall?.copyWith(color: AppTheme.errorColor))),
            BotonValle(texto: 'Guardar', icono: Icons.check_rounded, cargando: _guardando, onPressed: _guardar),
          ]),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('¿Con qué repartes?', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final v in Vehiculo.values)
                TarjetaValle(
                  padding: const EdgeInsets.all(8),
                  colorBorde: _vehiculo == v ? c.primario : null,
                  color: _vehiculo == v ? c.primario.withValues(alpha: 0.12) : null,
                  onTap: () => setState(() => _vehiculo = v),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(v.icono, size: 32, color: _vehiculo == v ? c.primario : c.textoSuave),
                      const SizedBox(height: 6),
                      Text(v.etiqueta, style: tema.labelLarge?.copyWith(fontWeight: _vehiculo == v ? FontWeight.w800 : FontWeight.w500)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_vehiculo.llevaPlaca) ...[
            CampoValle(controller: _placa, etiqueta: 'Placa', icono: Icons.pin_outlined, mayusculas: TextCapitalization.characters, maxLongitud: 9, ayuda: 'Ej: ABC-1234 (auto) o AB-123C (moto)'),
            const SizedBox(height: 14),
          ],
          CampoValle(controller: _color, etiqueta: 'Color (opcional)', icono: Icons.palette_outlined, mayusculas: TextCapitalization.sentences, maxLongitud: 30, ayuda: 'Ayuda al cliente y al negocio a reconocerte', accion: TextInputAction.done),
        ],
      ),
    );
  }
}
