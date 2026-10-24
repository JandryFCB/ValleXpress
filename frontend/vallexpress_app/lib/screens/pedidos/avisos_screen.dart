import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/abrir_pedido.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';

/// Abre los avisos: en el celular, la pantalla completa; en el computador, un panel pequeño bajo la campana (arriba a
/// la derecha) que se cierra al tocar fuera. Al tocar un aviso se cierra el panel y se abre lo que corresponde.
Future<void> abrirAvisos(BuildContext context) {
  if (!esEscritorio(context)) return Navigator.push(context, MaterialPageRoute(builder: (_) => const AvisosScreen()));
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (ctx) => Dialog(
      alignment: Alignment.topRight,
      insetPadding: const EdgeInsets.only(top: 70, right: margenWeb - 8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 400, height: (MediaQuery.sizeOf(ctx).height - 110).clamp(300, 560), child: AvisosScreen(panel: true, contextoPadre: contextoDeContenido(context))),
    ),
  );
}

/// Avisos (notificaciones): lo que pasó con tus pedidos. Los nuevos llegan en vivo. Tocar uno lo marca como leído
/// y abre su pedido.
class AvisosScreen extends StatefulWidget {
  const AvisosScreen({super.key, this.panel = false, this.contextoPadre});

  /// Dentro del panel del computador (sin barra de título de pantalla)
  final bool panel;

  /// Desde dónde se abrió el panel: ahí se abre el aviso tocado (el panel se cierra antes)
  final BuildContext? contextoPadre;

  @override
  State<AvisosScreen> createState() => _AvisosScreenState();
}

class _AvisosScreenState extends State<AvisosScreen> {
  List<Aviso> _avisos = [];
  int _noLeidos = 0;
  bool _cargando = true;
  String? _error;
  StreamSubscription? _vivo;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.avisos.listen((a) {
      if (!mounted) return;
      setState(() {
        _avisos = [a, ..._avisos];
        _noLeidos++;
      });
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await PedidosService.avisos();
      if (!mounted) return;
      setState(() {
        _avisos = r.avisos;
        _noLeidos = r.noLeidas;
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  Future<void> _abrir(Aviso a) async {
    if (!a.leida) {
      setState(() {
        _avisos = [for (final x in _avisos) x.id == a.id ? x.marcada() : x];
        _noLeidos = (_noLeidos - 1).clamp(0, 1 << 30);
      });
      PedidosService.marcarAvisoLeido(a.id).catchError((_) {});
    }
    final padre = widget.contextoPadre;
    if (widget.panel && padre != null) {
      Navigator.pop(context); // cierra el panel
      if (padre.mounted) await abrirAviso(padre, tipo: a.tipo, pedidoId: a.pedidoId);
      return;
    }
    await abrirAviso(context, tipo: a.tipo, pedidoId: a.pedidoId); // cada rol lo ve en su pantalla
  }

  Future<void> _leerTodos() async {
    try {
      await PedidosService.marcarTodosLeidos();
      if (!mounted) return;
      setState(() {
        _avisos = [for (final x in _avisos) x.marcada()];
        _noLeidos = 0;
      });
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.panel) {
      final tema = Theme.of(context).textTheme;
      return Material(
        color: context.colores.fondo,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Avisos', style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  if (_noLeidos > 0) TextButton(onPressed: _leerTodos, child: const Text('Leer todos')),
                  IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Expanded(child: _contenido()),
          ],
        ),
      );
    }
    return FondoValle(
      titulo: 'Avisos',
      acciones: [if (_noLeidos > 0) TextButton(onPressed: _leerTodos, child: const Text('Leer todos'))],
      child: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 6);
    if (_error != null && _avisos.isEmpty) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tus avisos', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_avisos.isEmpty) {
      return const EstadoVacio(icono: Icons.notifications_none_rounded, titulo: 'Todo tranquilo por aquí', mensaje: 'Te avisaremos cuando tu pedido cambie de estado.');
    }
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _avisos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _avisos[i];
          return Aparecer(key: ValueKey('aviso-${a.id}'), indice: i, child: TarjetaValle(
            onTap: () => _abrir(a),
            padding: const EdgeInsets.all(14),
            color: a.leida ? null : c.primario.withValues(alpha: 0.08),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: a.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(a.icono, color: a.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(a.titulo, style: tema.titleSmall?.copyWith(fontWeight: a.leida ? FontWeight.w600 : FontWeight.w800))),
                          if (!a.leida) Container(width: 9, height: 9, decoration: BoxDecoration(color: c.primario, shape: BoxShape.circle)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(a.mensaje, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                      if (a.fecha != null) ...[
                        const SizedBox(height: 4),
                        Text(Formato.hace(a.fecha!), style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ));
        },
      ),
    );
  }
}
