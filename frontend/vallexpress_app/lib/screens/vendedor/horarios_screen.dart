import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/negocio.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../widgets/ui/ui.dart';

/// Horario de atención de la semana. Cada día: abierto o cerrado, con hora de apertura y de cierre.
/// Si el cierre es antes que la apertura, se entiende que cruza la medianoche (ej. 18:00 a 02:00).
class HorariosScreen extends StatefulWidget {
  const HorariosScreen({super.key, required this.actuales});

  final List<HorarioDia> actuales;

  @override
  State<HorariosScreen> createState() => _HorariosScreenState();
}

class _HorariosScreenState extends State<HorariosScreen> {
  late List<HorarioDia> _dias;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Si aún no hay horario, se propone 08:00 a 20:00 todos los días
    _dias = List.generate(7, (i) {
      final dia = i + 1;
      return widget.actuales.where((h) => h.dia == dia).firstOrNull ?? HorarioDia(dia: dia, apertura: '08:00', cierre: '20:00');
    });
  }

  TimeOfDay _aHora(String? t) => TimeOfDay(hour: int.parse((t ?? '08:00').substring(0, 2)), minute: int.parse((t ?? '08:00').substring(3, 5)));
  String _aTexto(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _elegirHora(int i, {required bool apertura}) async {
    final d = _dias[i];
    final elegida = await showTimePicker(
      context: context,
      initialTime: _aHora(apertura ? d.apertura : d.cierre),
      helpText: apertura ? 'Hora de apertura · ${d.nombreDia}' : 'Hora de cierre · ${d.nombreDia}',
      builder: (ctx, hijo) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: hijo!),
    );
    if (elegida == null) return;
    setState(() {
      _dias[i] = HorarioDia(
        dia: d.dia,
        cerrado: false,
        apertura: apertura ? _aTexto(elegida) : d.apertura,
        cierre: apertura ? d.cierre : _aTexto(elegida),
      );
    });
  }

  void _copiarATodos(int i) {
    final base = _dias[i];
    setState(() {
      _dias = [for (final d in _dias) HorarioDia(dia: d.dia, cerrado: base.cerrado, apertura: base.apertura, cierre: base.cierre)];
    });
    mostrarMensaje(context, 'Se copió el horario del ${base.nombreDia.toLowerCase()} a todos los días');
  }

  Future<void> _guardar() async {
    final iguales = _dias.where((d) => !d.cerrado && d.apertura == d.cierre).firstOrNull;
    if (iguales != null) {
      mostrarError(context, 'El ${iguales.nombreDia.toLowerCase()} tiene la misma hora de apertura y de cierre');
      return;
    }
    setState(() => _guardando = true);
    try {
      final negocio = await CatalogoService.fijarHorarios(_dias);
      if (!mounted) return;
      mostrarExito(context, 'Horario guardado');
      Navigator.pop(context, negocio);
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
    final hoy = DateTime.now().weekday;

    return FondoValle(
      anchoEscritorio: 760, // computador: una columna centrada (estirada se ve vacía)
      titulo: 'Horario de atención',
      barraInferior: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
          child: BotonValle(texto: 'Guardar horario', icono: Icons.check_rounded, cargando: _guardando, onPressed: _guardar),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _dias.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Tus clientes ven si estás abierto según este horario y el interruptor de "Abierto".', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            );
          }
          final idx = i - 1;
          final d = _dias[idx];
          return TarjetaValle(
            colorBorde: d.dia == hoy ? c.primario : null,
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.nombreDia, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      if (d.dia == hoy) Text('Hoy', style: tema.labelSmall?.copyWith(color: c.primario)),
                    ],
                  ),
                ),
                Expanded(
                  child: d.cerrado
                      ? Text('Cerrado', style: tema.bodyMedium?.copyWith(color: c.textoSuave))
                      : Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            _BotonHora(texto: d.apertura ?? '--:--', onTap: () => _elegirHora(idx, apertura: true)),
                            Text('a', style: tema.bodySmall),
                            _BotonHora(texto: d.cierre ?? '--:--', onTap: () => _elegirHora(idx, apertura: false)),
                          ],
                        ),
                ),
                Switch(
                  value: !d.cerrado,
                  onChanged: (abierto) => setState(() {
                    _dias[idx] = abierto
                        ? HorarioDia(dia: d.dia, apertura: d.apertura ?? '08:00', cierre: d.cierre ?? '20:00')
                        : HorarioDia(dia: d.dia, cerrado: true, apertura: d.apertura, cierre: d.cierre);
                  }),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Más',
                  icon: Icon(Icons.more_vert_rounded, color: c.textoSuave),
                  onSelected: (_) => _copiarATodos(idx),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'copiar', child: Text('Copiar a todos los días'))],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BotonHora extends StatelessWidget {
  const _BotonHora({required this.texto, required this.onTap});

  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Material(
      color: c.primario.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(texto, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.primario, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ),
    );
  }
}
