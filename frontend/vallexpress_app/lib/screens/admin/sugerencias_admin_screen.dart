import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/api_error.dart';
import '../../services/sugerencia_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../profile/ayudanos_screen.dart' show tiposSugerencia;

/// Sugerencias que mandan clientes, vendedores y repartidores: las nuevas primero. Tocar una la abre para marcarla
/// como leída, responder (a la persona le llega el aviso) o darla por atendida.
class SugerenciasAdminScreen extends StatefulWidget {
  const SugerenciasAdminScreen({super.key});

  @override
  State<SugerenciasAdminScreen> createState() => _SugerenciasAdminScreenState();
}

class _SugerenciasAdminScreenState extends State<SugerenciasAdminScreen> {
  static const _estados = [(null, 'Todas'), ('nueva', 'Nuevas'), ('leida', 'Leídas'), ('atendida', 'Atendidas')];
  static const _roles = {'cliente': 'Cliente', 'vendedor': 'Negocio', 'repartidor': 'Repartidor', 'administrador': 'Admin'};

  String? _estado;
  List<Sugerencia>? _lista;
  Map<String, int> _conteos = {};
  double? _satisfaccion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await SugerenciaService.todas(estado: _estado);
      if (mounted) setState(() => (_lista = r.lista, _conteos = r.conteos, _satisfaccion = r.satisfaccion, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _abrir(Sugerencia s) async {
    // Al abrir una nueva se marca como leída
    if (s.estado == 'nueva') {
      SugerenciaService.atender(s.id, estado: 'leida').then((_) => _cargar()).catchError((_) {});
    }
    final respuesta = TextEditingController(text: s.respuesta ?? '');
    final accion = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(tiposSugerencia[s.tipo]?.$2, color: tiposSugerencia[s.tipo]?.$3),
              const SizedBox(width: 8),
              Expanded(child: Text('${s.nombre ?? s.usuario} · ${_roles[s.rol] ?? s.rol}', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            Text('@${s.usuario}${s.versionApp != null ? ' · app ${s.versionApp}' : ''}${s.fecha != null ? ' · ${Formato.fechaRelativa(s.fecha!)}' : ''}', style: Theme.of(ctx).textTheme.bodySmall),
            if (s.satisfaccion != null)
              Row(children: [for (var i = 1; i <= 5; i++) Icon(i <= s.satisfaccion! ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: AppTheme.accentColor)]),
            const SizedBox(height: 10),
            Text(s.mensaje, style: Theme.of(ctx).textTheme.bodyLarge),
            const SizedBox(height: 16),
            TextField(controller: respuesta, maxLines: 4, maxLength: 1000, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Respuesta (le llega como aviso)')),
            const SizedBox(height: 8),
            BotonValle(texto: 'Responder', icono: Icons.send_rounded, onPressed: () => Navigator.pop(ctx, 'responder')),
            const SizedBox(height: 8),
            if (s.estado != 'atendida') BotonValle(texto: 'Marcar como atendida (sin responder)', tipo: TipoBoton.texto, onPressed: () => Navigator.pop(ctx, 'atendida')),
          ]),
        ),
      ),
    );
    if (accion == null || !mounted) return;
    try {
      if (accion == 'responder') {
        if (respuesta.text.trim().isEmpty) return mostrarError(context, 'Escribe la respuesta');
        await SugerenciaService.atender(s.id, respuesta: respuesta.text.trim(), estado: 'atendida');
        if (mounted) mostrarExito(context, 'Respuesta enviada');
      } else {
        await SugerenciaService.atender(s.id, estado: 'atendida');
      }
      HapticFeedback.selectionClick();
      _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final lista = _lista;
    return FondoValle(
      appBar: AppBar(title: const Text('Sugerencias')),
      child: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              for (final (valor, texto) in _estados)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(valor == null || _conteos[valor] == null ? texto : '$texto · ${_conteos[valor]}'),
                    selected: _estado == valor,
                    onSelected: (_) {
                      setState(() => (_estado = valor, _lista = null));
                      _cargar();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_satisfaccion != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              const Icon(Icons.star_rounded, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Text('Satisfacción promedio: ${_satisfaccion!.toStringAsFixed(1)} de 5', style: tema.titleSmall),
            ]),
          ),
        Expanded(
          child: lista == null
              ? (_error != null
                  ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar las sugerencias', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
                  : const EsqueletoLista(cantidad: 4, conImagen: false))
              : lista.isEmpty
                  ? const EstadoVacio(icono: Icons.forum_outlined, titulo: 'Aún no hay mensajes', mensaje: 'Aquí verás las ideas, problemas y felicitaciones de tus usuarios.')
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: lista.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final s = lista[i];
                          return TarjetaValle(
                            onTap: () => _abrir(s),
                            colorBorde: s.estado == 'nueva' ? AppTheme.accentColor.withValues(alpha: 0.7) : null,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(tiposSugerencia[s.tipo]?.$2, size: 18, color: tiposSugerencia[s.tipo]?.$3),
                                const SizedBox(width: 6),
                                Expanded(child: Text('${s.nombre ?? s.usuario} · ${_roles[s.rol] ?? s.rol}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                InsigniaValle(
                                  switch (s.estado) { 'atendida' => 'Atendida', 'leida' => 'Leída', _ => 'Nueva' },
                                  color: switch (s.estado) { 'atendida' => AppTheme.successColor, 'leida' => AppTheme.infoColor, _ => AppTheme.accentColor },
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Text(s.mensaje, maxLines: 3, overflow: TextOverflow.ellipsis, style: tema.bodyMedium),
                              if (s.fecha != null) ...[const SizedBox(height: 4), Text(Formato.fechaRelativa(s.fecha!), style: tema.bodySmall?.copyWith(color: c.textoSuave))],
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
