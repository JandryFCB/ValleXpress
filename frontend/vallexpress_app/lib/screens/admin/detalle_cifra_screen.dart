import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/admin.dart';
import '../../models/pedido.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import 'pedidos_admin_screen.dart';

/// Detalle de una cifra del resumen, como el estado de cuenta de un banco: el total arriba, las cifras que lo
/// componen y los movimientos (por local o repartidor, y uno por uno). Tocar un pedido lo abre.
///   pedidos · ventas · ganancia · envios → por día, 7 días o 30 días
///   encurso · enlinea                    → lo que pasa ahora (se actualiza solo)
class DetalleCifraScreen extends StatefulWidget {
  const DetalleCifraScreen({super.key, required this.tipo, required this.titulo, required this.icono, required this.color});

  final String tipo;
  final String titulo;
  final IconData icono;
  final Color color;

  @override
  State<DetalleCifraScreen> createState() => _DetalleCifraScreenState();
}

class _DetalleCifraScreenState extends State<DetalleCifraScreen> {
  DetalleCifra? _d;
  String? _error;
  String _rango = 'hoy';
  StreamSubscription? _vivo;
  Timer? _espera;

  bool get _enVivo => widget.tipo == 'encurso' || widget.tipo == 'enlinea';

  @override
  void initState() {
    super.initState();
    _cargar();
    // Lo que pasa ahora se refresca con cada cambio de un pedido (agrupando ráfagas en una sola recarga)
    _vivo = TiempoReal.instancia.cambios().listen((_) {
      _espera?.cancel();
      _espera = Timer(const Duration(milliseconds: 800), _cargar);
    });
  }

  @override
  void dispose() {
    _vivo?.cancel();
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final d = await AdminService.detalleCifra(widget.tipo, rango: _rango);
      if (mounted) setState(() => (_d = d, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  void _cambiarRango(String r) {
    setState(() => (_rango = r, _d = null));
    _cargar();
  }

  static String valor(num v, String formato) => switch (formato) {
        'dinero' => Formato.dinero(v),
        'entregas' => v == 1 ? '1 entrega' : '${v.toInt()} entregas',
        _ => '${v.toInt()}',
      };

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return FondoValle(
      appBar: AppBar(title: Text(widget.titulo)),
      child: Column(
        children: [
          if (!_enVivo)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'hoy', label: Text('Hoy')), ButtonSegment(value: 'semana', label: Text('7 días')), ButtonSegment(value: 'mes', label: Text('30 días'))],
                  selected: {_rango},
                  onSelectionChanged: (v) => _cambiarRango(v.first),
                ),
              ),
            ),
          Expanded(
            child: d == null
                ? (_error != null
                    ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el detalle', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
                    : const EsqueletoLista(cantidad: 5, conImagen: false))
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
                        Aparecer(child: _Encabezado(d: d, icono: widget.icono, color: widget.color, enVivo: _enVivo)),
                        for (final (i, s) in d.secciones.indexed) ...[
                          EncabezadoSeccion(s.titulo, subtitulo: s.filas.isEmpty ? null : (s.filas.length == 1 ? '1 registro' : '${s.filas.length} registros')),
                          Aparecer(
                            indice: i + 1,
                            child: s.filas.isEmpty
                                ? TarjetaValle(child: Text('Sin movimientos ${_enVivo ? 'en este momento' : 'en este periodo'}', style: TextStyle(color: context.colores.textoSuave)))
                                : TarjetaValle(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Column(
                                      children: [
                                        for (final (n, f) in s.filas.indexed) ...[
                                          if (n > 0) Divider(height: 1, indent: 64, color: context.colores.borde),
                                          _Fila(f: f, color: widget.color, enVivo: _enVivo),
                                        ],
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.d, required this.icono, required this.color, required this.enVivo});

  final DetalleCifra d;
  final IconData icono;
  final Color color;
  final bool enVivo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final periodo = switch (d.rango) { 'semana' => 'Últimos 7 días', 'mes' => 'Últimos 30 días', 'ahora' => 'En este momento', _ => 'Hoy' };
    return TarjetaValle(
      color: color.withValues(alpha: 0.1),
      colorBorde: color.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(d.total.etiqueta, style: tema.titleSmall?.copyWith(color: c.textoSuave))),
            if (enVivo) InsigniaValle('En vivo', color: AppTheme.successColor, icono: Icons.circle) else Text(periodo, style: tema.labelMedium?.copyWith(color: c.textoSuave)),
          ]),
          const SizedBox(height: 8),
          d.total.formato == 'dinero'
              ? DineroAnimado(d.total.valor.toDouble(), estilo: tema.displaySmall?.copyWith(fontWeight: FontWeight.w800))
              : Text(_DetalleCifraScreenState.valor(d.total.valor, d.total.formato), style: tema.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          if (d.resumen.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in d.resumen)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: c.tarjeta, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.borde)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(r.etiqueta, style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                        Text(_DetalleCifraScreenState.valor(r.valor, r.formato), style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.f, required this.color, required this.enVivo});

  final FilaCifra f;
  final Color color;
  final bool enVivo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final estado = f.estado == null ? null : EstadoPedido.deCodigo(f.estado);
    final icono = switch (f.icono) {
      'local' => Icons.storefront_rounded,
      'repartidor' => Icons.two_wheeler_rounded,
      'pago' => Icons.savings_rounded,
      _ => estado?.icono ?? Icons.receipt_long_rounded,
    };
    final colorIcono = f.icono == 'repartidor' ? (f.ocupado ? AppTheme.warningColor : AppTheme.successColor) : (estado?.color ?? color);
    // Fecha: la hora del pedido o del pago; del repartidor, cuándo llegó su última ubicación
    final cuando = f.fecha == null ? null : (f.icono == 'repartidor' ? 'ubicación ${Formato.hace(f.fecha!)}' : (enVivo ? Formato.hace(f.fecha!) : Formato.fechaRelativa(f.fecha!)));

    return InkWell(
      onTap: f.pedidoId == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoAdminScreen(pedidoId: f.pedidoId!))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 20, backgroundColor: colorIcono.withValues(alpha: 0.15), child: Icon(icono, color: colorIcono, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (f.detalle.isNotEmpty) Text(f.detalle, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                  if (estado != null || cuando != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (estado != null) InsigniaValle(estado.etiqueta, color: estado.color),
                        if (cuando != null) Text(cuando, style: tema.labelSmall?.copyWith(color: c.textoSuave)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_DetalleCifraScreenState.valor(f.valor, f.formato), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: f.formato == 'dinero' ? c.primario : null)),
          ],
        ),
      ),
    );
  }
}
