import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/suscripcion.dart';
import '../../services/api_error.dart';
import '../../services/suscripcion_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../utils/imagen.dart';
import '../../widgets/estado_cuenta.dart';
import '../../widgets/ui/ui.dart';

/// Avisos que cambian el estado de la suscripción (el admin revisa un comprobante o registra un pago)
const avisosSuscripcion = {'suscripcion_pagada', 'comprobante_rechazado'};

/// Mi suscripción con ValleXpress (vendedor y repartidor): la cuota mensual, cada mes y si ya está pagado, cuánto
/// debo y a dónde transferir. Si un mes se vence sin pagar, el negocio no recibe pedidos y el repartidor no se conecta.
class MiSuscripcionScreen extends StatefulWidget {
  const MiSuscripcionScreen({super.key});

  @override
  State<MiSuscripcionScreen> createState() => _MiSuscripcionScreenState();
}

class _MiSuscripcionScreenState extends State<MiSuscripcionScreen> {
  EstadoSuscripcion? _cuenta;
  String? _error;
  StreamSubscription? _vivo;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios(tiposAviso: avisosSuscripcion, sinPedidos: true).listen((_) => _cargar());
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final c = await SuscripcionService.estado();
      if (mounted) setState(() => (_cuenta = c, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  // Foto del comprobante (cámara o galería) + número de la transferencia (opcional)
  Future<void> _subirComprobante(MesSuscripcion m) async {
    final imagen = await elegirImagenBase64(context, titulo: 'Foto del comprobante');
    if (imagen == null || !mounted) return;
    final referencia = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m.titulo}: ${Formato.dinero(m.monto)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Lo revisamos y te avisamos. Mientras tanto, este mes no te bloquea.'),
          const SizedBox(height: 12),
          TextField(controller: referencia, maxLength: 100, decoration: const InputDecoration(labelText: 'Nº de transferencia (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (enviar != true || !mounted) return;
    try {
      final c = await SuscripcionService.subirComprobante(mes: m.mes, imagen: imagen, referencia: referencia.text);
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarExito(context, 'Comprobante enviado. Te avisamos cuando lo revisemos');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(
      appBar: AppBar(title: const Text('Mi suscripción')),
      child: _cuenta == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tu suscripción', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [EstadoSuscripcionVista(cuenta: _cuenta!, onSubirComprobante: _subirComprobante)],
              ),
            ),
    );
  }
}

/// Aviso en el inicio del vendedor o repartidor cuando debe su suscripción (más fuerte si ya está bloqueado) o tiene
/// un comprobante en revisión. Al día no ocupa espacio. Se recarga cuando el admin revisa un pago y al volver a la app.
class AvisoSuscripcion extends StatefulWidget {
  const AvisoSuscripcion({super.key, this.margen = const EdgeInsets.fromLTRB(16, 12, 16, 0)});

  final EdgeInsets margen;

  @override
  State<AvisoSuscripcion> createState() => _AvisoSuscripcionState();
}

class _AvisoSuscripcionState extends State<AvisoSuscripcion> with WidgetsBindingObserver {
  EstadoSuscripcion? _cuenta;
  StreamSubscription? _vivo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
    _vivo = TiempoReal.instancia.cambios(tiposAviso: avisosSuscripcion, sinPedidos: true).listen((_) => _cargar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vivo?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    try {
      final c = await SuscripcionService.estado();
      if (mounted) setState(() => _cuenta = c);
    } catch (_) {
      // sin conexión: no se muestra nada
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cuenta;
    final tema = Theme.of(context).textTheme;
    if (c == null || !c.aplica || (c.saldoPendiente <= 0 && c.enRevision == 0)) return const SizedBox(width: double.infinity);
    final soloRevision = !c.bloqueado && c.saldoPendiente <= 0;
    final color = c.bloqueado ? AppTheme.errorColor : (soloRevision ? AppTheme.infoColor : AppTheme.warningColor);
    final bloqueo = c.tipo == 'vendedor' ? 'No estás recibiendo pedidos' : 'No puedes conectarte';
    final debeMes = c.meses.where((m) => m.estado == EstadoMes.porPagar).firstOrNull;
    final (icono, titulo, detalle) = c.bloqueado
        ? (Icons.block_rounded, bloqueo, 'Tu suscripción está vencida (${Formato.dinero(c.saldoPendiente)}). Toca para ver cómo pagar')
        : soloRevision
            ? (Icons.hourglass_top_rounded, 'Comprobante en revisión', 'Recibimos tu comprobante. Te avisamos cuando lo revisemos')
            : (
                Icons.account_balance_wallet_rounded,
                'Suscripción por pagar: ${Formato.dinero(c.saldoPendiente)}',
                debeMes != null ? 'Paga hasta el ${debeMes.vence.day}/${debeMes.vence.month} para seguir trabajando. Toca para ver a dónde transferir' : 'Toca para ver el detalle y a dónde transferir',
              );
    return Padding(
      padding: widget.margen,
      child: TarjetaValle(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const MiSuscripcionScreen()));
          _cargar();
        },
        color: color.withValues(alpha: 0.12),
        colorBorde: color.withValues(alpha: 0.6),
        child: Row(
          children: [
            Icon(icono, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(detalle, style: tema.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
