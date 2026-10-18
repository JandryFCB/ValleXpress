import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/reputacion.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';

/// Reputación del repartidor: su promedio (clientes y negocios), las advertencias y los últimos comentarios.
/// La usa el repartidor ("Mi reputación") y el administrador (con quién calificó y el botón para advertir).
class ReputacionVista extends StatelessWidget {
  const ReputacionVista({super.key, required this.r, this.paraAdmin = false});

  final Reputacion r;
  final bool paraAdmin;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final color = r.total == 0 ? c.textoSuave : r.promedio >= 4 ? AppTheme.successColor : r.promedio >= 3 ? AppTheme.warningColor : AppTheme.errorColor;
    Widget cifra(String titulo, double promedio, int total) => Expanded(
          child: Column(children: [
            Text(total == 0 ? '—' : promedio.toStringAsFixed(1), style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('$titulo ($total)', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TarjetaValle(
          color: color.withValues(alpha: 0.1),
          colorBorde: color.withValues(alpha: 0.5),
          child: Column(children: [
            Row(children: [
              Icon(Icons.star_rounded, color: AppTheme.accentColor, size: 40),
              const SizedBox(width: 10),
              Text(r.total == 0 ? 'Sin calificaciones' : r.promedio.toStringAsFixed(1), style: tema.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(r.total == 1 ? '1 calificación' : '${r.total} calificaciones', style: tema.bodySmall),
            ]),
            const SizedBox(height: 12),
            Row(children: [cifra('Clientes', r.promedioClientes, r.totalClientes), cifra('Negocios', r.promedioNegocios, r.totalNegocios)]),
            if (!paraAdmin) ...[
              const SizedBox(height: 10),
              Text('Trata bien a clientes y negocios y entrega a tiempo: con quejas recibirás advertencias y tu cuenta puede ser dada de baja.', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            ],
          ]),
        ),
        if (r.advertencias.isNotEmpty) ...[
          EncabezadoSeccion(r.advertencias.length == 1 ? '1 advertencia' : '${r.advertencias.length} advertencias'),
          for (final a in r.advertencias)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TarjetaValle(
                color: AppTheme.errorColor.withValues(alpha: 0.08),
                colorBorde: AppTheme.errorColor.withValues(alpha: 0.4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.motivo, style: tema.bodyMedium),
                      if (a.fecha != null) Text(Formato.fechaRelativa(a.fecha!), style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
        EncabezadoSeccion('Últimas calificaciones', subtitulo: paraAdmin ? null : 'No mostramos quién te calificó'),
        if (r.calificaciones.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: EstadoVacio(icono: Icons.star_outline_rounded, titulo: 'Aún no hay calificaciones', mensaje: 'Cuando entregues pedidos, aquí verás lo que opinan de tu servicio.'))
        else
          for (final k in r.calificaciones)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TarjetaValle(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    for (var i = 1; i <= 5; i++) Icon(i <= k.puntuacion ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        paraAdmin && k.autor != null ? '${k.origen == 'negocio' ? 'Negocio' : 'Cliente'}: ${k.autor}' : (k.origen == 'negocio' ? 'Un negocio' : 'Un cliente'),
                        style: tema.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('#${k.pedidoId}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                  ]),
                  if (k.comentario != null && k.comentario!.isNotEmpty) ...[const SizedBox(height: 4), Text('"${k.comentario}"', style: tema.bodyMedium)],
                  if (k.fecha != null) Text(Formato.fechaRelativa(k.fecha!), style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                ]),
              ),
            ),
      ],
    );
  }
}

/// "Mi reputación" del repartidor
class MiReputacionScreen extends StatefulWidget {
  const MiReputacionScreen({super.key});

  @override
  State<MiReputacionScreen> createState() => _MiReputacionScreenState();
}

class _MiReputacionScreenState extends State<MiReputacionScreen> {
  Reputacion? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await PedidosService.miReputacion();
      if (mounted) setState(() => (_r = r, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) => FondoValle(
        appBar: AppBar(title: const Text('Mi reputación')),
        child: _r == null
            ? (_error != null
                ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tu reputación', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
                : const EsqueletoLista(cantidad: 3, conImagen: false))
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [ReputacionVista(r: _r!)]),
              ),
      );
}
