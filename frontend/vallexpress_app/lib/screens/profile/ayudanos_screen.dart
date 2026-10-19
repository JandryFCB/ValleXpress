import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/api_error.dart';
import '../../services/sugerencia_service.dart';
import '../../services/version_app.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';

const tiposSugerencia = {
  'sugerencia': ('Una idea', Icons.lightbulb_rounded, AppTheme.accentColor),
  'problema': ('Algo falla', Icons.bug_report_rounded, AppTheme.errorColor),
  'felicitacion': ('Me gusta', Icons.favorite_rounded, AppTheme.successColor),
};

/// "Ayúdanos a mejorar ValleXpress": clientes, vendedores y repartidores mandan una idea, reportan algo que falla o
/// cuentan lo que les gusta, y ven la respuesta del equipo.
class AyudanosScreen extends StatefulWidget {
  const AyudanosScreen({super.key});

  @override
  State<AyudanosScreen> createState() => _AyudanosScreenState();
}

class _AyudanosScreenState extends State<AyudanosScreen> {
  final _mensaje = TextEditingController();
  String _tipo = 'sugerencia';
  int? _satisfaccion;
  bool _enviando = false;
  List<Sugerencia>? _mias;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _mensaje.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final m = await SugerenciaService.mias();
      if (mounted) setState(() => _mias = m);
    } catch (_) {
      if (mounted) setState(() => _mias = const []);
    }
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    if (_mensaje.text.trim().length < 10) return mostrarError(context, 'Cuéntanos un poco más (al menos 10 letras)');
    setState(() => _enviando = true);
    try {
      final nueva = await SugerenciaService.enviar(tipo: _tipo, mensaje: _mensaje.text, satisfaccion: _satisfaccion, versionApp: await VersionApp.texto());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => (_mias = [nueva, ...?_mias], _satisfaccion = null));
      _mensaje.clear();
      Confeti.lanzar(context);
      mostrarExito(context, '¡Gracias! Leemos todos los mensajes');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return FondoValle(
      appBar: AppBar(title: const Text('Ayúdanos a mejorar')),
      child: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Tu opinión hace mejor a ValleXpress. Cuéntanos qué te gustaría, qué falla o qué te gusta.', style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
            const SizedBox(height: 16),
            TarjetaValle(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('¿Qué nos quieres contar?', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in tiposSugerencia.entries)
                    ChoiceChip(
                      avatar: Icon(e.value.$2, size: 18, color: _tipo == e.key ? null : e.value.$3),
                      label: Text(e.value.$1),
                      selected: _tipo == e.key,
                      onSelected: (_) => setState(() => _tipo = e.key),
                    ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _mensaje,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: switch (_tipo) {
                      'problema' => '¿Qué pasó y en qué pantalla? Así lo arreglamos más rápido',
                      'felicitacion' => '¿Qué es lo que más te gusta?',
                      _ => '¿Qué te gustaría que tenga ValleXpress?',
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text('¿Qué tan contento estás con la app? (opcional)', style: tema.bodySmall),
                Row(children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _satisfaccion = _satisfaccion == i ? null : i),
                      icon: Icon(i <= (_satisfaccion ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded, color: AppTheme.accentColor, size: 30),
                    ),
                ]),
                const SizedBox(height: 8),
                BotonValle(texto: 'Enviar', icono: Icons.send_rounded, cargando: _enviando, onPressed: _enviar),
              ]),
            ),
            if (_mias != null && _mias!.isNotEmpty) ...[
              const EncabezadoSeccion('Tus mensajes'),
              for (final s in _mias!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TarjetaValle(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(tiposSugerencia[s.tipo]?.$2 ?? Icons.chat_rounded, size: 18, color: tiposSugerencia[s.tipo]?.$3),
                        const SizedBox(width: 6),
                        Expanded(child: Text(s.fecha == null ? '' : Formato.fechaRelativa(s.fecha!), style: tema.bodySmall?.copyWith(color: c.textoSuave))),
                        InsigniaValle(
                          switch (s.estado) { 'atendida' => 'Respondido', 'leida' => 'Leído', _ => 'Enviado' },
                          color: switch (s.estado) { 'atendida' => AppTheme.successColor, 'leida' => AppTheme.infoColor, _ => Colors.grey },
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(s.mensaje, style: tema.bodyMedium),
                      if (s.respuesta != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Respuesta de ValleXpress', style: tema.labelMedium?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(s.respuesta!, style: tema.bodyMedium),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
