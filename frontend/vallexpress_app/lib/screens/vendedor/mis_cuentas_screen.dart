import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/liquidacion.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/formato.dart';
import '../../utils/imagen.dart';
import '../../widgets/estado_cuenta.dart';
import '../../widgets/ui/ui.dart';

/// Mis cuentas con ValleXpress: cada semana, lo vendido, la comisión (10 %) y si ya está pagada; cuánto debo y a
/// dónde transferir. Si una semana se vence sin pagar, el negocio deja de recibir pedidos hasta ponerse al día.
class MisCuentasScreen extends StatefulWidget {
  const MisCuentasScreen({super.key});

  @override
  State<MisCuentasScreen> createState() => _MisCuentasScreenState();
}

class _MisCuentasScreenState extends State<MisCuentasScreen> {
  EstadoDeCuenta? _cuenta;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final c = await CatalogoService.misLiquidaciones();
      if (mounted) setState(() => (_cuenta = c, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  // Foto del comprobante (cámara o galería) + número de la transferencia (opcional)
  Future<void> _subirComprobante(SemanaLiquidacion s) async {
    final imagen = await elegirImagenBase64(context, titulo: 'Foto del comprobante');
    if (imagen == null || !mounted) return;
    final referencia = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Comprobante de ${Formato.dinero(s.comision)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Lo revisamos y te avisamos. Mientras tanto, esta semana no te bloquea.'),
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
      final c = await CatalogoService.subirComprobante(semana: s.codigoSemana, imagen: imagen, referencia: referencia.text);
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
      appBar: AppBar(title: const Text('Mis cuentas con ValleXpress')),
      child: _cuenta == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tus cuentas', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [EstadoCuentaVista(cuenta: _cuenta!, onSubirComprobante: _subirComprobante)],
              ),
            ),
    );
  }
}

/// Aviso en el inicio del vendedor cuando debe comisiones (y más fuerte si ya está bloqueado). Si ya envió el
/// comprobante muestra que está en revisión. Si está al día no ocupa espacio. Se recarga cuando el admin revisa un
/// pago y al volver a la app.
class AvisoCuenta extends StatefulWidget {
  const AvisoCuenta({super.key, this.margen = const EdgeInsets.fromLTRB(16, 12, 16, 0)});

  final EdgeInsets margen;

  @override
  State<AvisoCuenta> createState() => _AvisoCuentaState();
}

class _AvisoCuentaState extends State<AvisoCuenta> {
  EstadoDeCuenta? _cuenta;
  StreamSubscription? _vivo;

  @override
  void initState() {
    super.initState();
    _cargar();
    _vivo = TiempoReal.instancia.cambios(tiposAviso: const {'liquidacion_pagada', 'comprobante_rechazado'}, sinPedidos: true).listen((_) => _cargar());
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final c = await CatalogoService.misLiquidaciones();
      if (mounted) setState(() => _cuenta = c);
    } catch (_) {
      // sin negocio todavía o sin conexión: no se muestra nada
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cuenta;
    final tema = Theme.of(context).textTheme;
    if (c == null || c.saldoPendiente <= 0) return const SizedBox(width: double.infinity);
    final soloRevision = !c.bloqueado && c.saldoPorPagar <= 0; // todo lo que debía ya tiene comprobante
    final color = c.bloqueado ? AppTheme.errorColor : (soloRevision ? AppTheme.infoColor : AppTheme.warningColor);
    final (icono, titulo, detalle) = c.bloqueado
        ? (Icons.block_rounded, 'No estás recibiendo pedidos', 'Tienes ${Formato.dinero(c.saldoPorPagar)} vencidos. Toca para ver cómo pagar')
        : soloRevision
            ? (Icons.hourglass_top_rounded, 'Comprobante en revisión', 'Recibimos tu pago de ${Formato.dinero(c.saldoEnRevision)}. Te avisamos cuando lo revisemos')
            : (
                Icons.account_balance_wallet_rounded,
                'Comisión por pagar: ${Formato.dinero(c.saldoPorPagar)}',
                c.saldoEnRevision > 0
                    ? '${Formato.dinero(c.saldoEnRevision)} ya están en revisión. Toca para ver el detalle'
                    : 'Toca para ver el detalle y a dónde transferir',
              );
    return Padding(
      padding: widget.margen,
      child: TarjetaValle(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const MisCuentasScreen()));
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
