import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/pedido.dart';
import '../services/api_error.dart';
import '../services/pedidos_service.dart';
import '../utils/formato.dart';
import '../utils/imagen.dart';
import 'cuentas_banco.dart';
import 'estado_cuenta.dart' show verComprobante;
import 'ui/ui.dart';

/// Pago por transferencia de un pedido, del lado del CLIENTE:
///   * pendiente: le explica que verá las cuentas cuando el negocio confirme
///   * confirmado y sin pagar: las cuentas del negocio para copiar y el botón para subir el comprobante (o el que
///     ya subió, mientras el negocio lo revisa; o el motivo si el negocio dijo que no le llegó)
///   * pagado: "Pago recibido"
class PagoTransferenciaCliente extends StatelessWidget {
  const PagoTransferenciaCliente({super.key, required this.pedido, required this.onActualizado});

  final Pedido pedido;
  final ValueChanged<Pedido> onActualizado;

  Future<void> _subir(BuildContext context) async {
    final imagen = await elegirImagenBase64(context, titulo: 'Foto del comprobante');
    if (imagen == null || !context.mounted) return;
    final referencia = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Transferencia de ${Formato.dinero(pedido.total)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${pedido.negocioNombre} revisará que le llegó y empezará a preparar tu pedido.'),
          const SizedBox(height: 12),
          TextField(controller: referencia, maxLength: 100, decoration: const InputDecoration(labelText: 'Nº de transferencia (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (enviar != true || !context.mounted) return;
    try {
      final p = await PedidosService.subirComprobante(pedido.id, imagen: imagen, referencia: referencia.text);
      onActualizado(p);
      if (context.mounted) mostrarExito(context, 'Comprobante enviado. Te avisamos cuando el negocio lo confirme');
    } catch (e) {
      if (context.mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final t = p.transferencia;
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    if (!p.esTransferencia || p.estado.fallido) return const SizedBox.shrink();
    if (p.pagado) {
      return const InsigniaValle('Pago recibido: el negocio confirmó tu transferencia', color: AppTheme.successColor, icono: Icons.verified_rounded);
    }
    if (p.estado == EstadoPedido.pendiente) {
      return const InsigniaValle('Pagas por transferencia: cuando el negocio confirme tu pedido verás sus cuentas aquí', color: AppTheme.infoColor, icono: Icons.account_balance_rounded);
    }
    final comp = t?.comprobante;
    return TarjetaValle(
      colorBorde: comp?.enviado == true ? null : AppTheme.warningColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_balance_rounded, color: comp?.enviado == true ? c.primario : AppTheme.warningColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(comp?.enviado == true ? 'Comprobante enviado' : 'Transfiere ${Formato.dinero(p.total)}', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 6),
          if (comp?.enviado == true) ...[
            Text('${p.negocioNombre} está revisando que le llegó. Te avisamos al confirmarlo.', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            const SizedBox(height: 10),
            ComprobanteMiniatura(comprobante: comp!),
          ] else ...[
            if (comp?.rechazado == true) ...[
              InsigniaValle('${p.negocioNombre} no recibió tu transferencia${comp!.motivo != null ? ': ${comp.motivo}' : ''}', color: AppTheme.errorColor, icono: Icons.report_gmailerrorred_rounded),
              const SizedBox(height: 10),
            ],
            Text(
              '${p.negocioNombre} confirmó tu pedido. Transfiere a ${(t?.cuentas.length ?? 0) > 1 ? 'una de estas cuentas' : 'esta cuenta'} y sube la foto del comprobante para que empiece a prepararlo.',
              style: tema.bodySmall?.copyWith(color: c.textoSuave),
            ),
            const SizedBox(height: 10),
            for (final cuenta in t?.cuentas ?? const []) Padding(padding: const EdgeInsets.only(bottom: 10), child: TarjetaCuentaBanco(cuenta: cuenta)),
            if (t?.puedeSubir == true) BotonValle(texto: 'Subir comprobante', icono: Icons.receipt_long_rounded, onPressed: () => _subir(context)),
          ],
        ],
      ),
    );
  }
}

/// Foto del comprobante con su estado (tocarla la abre en grande)
class ComprobanteMiniatura extends StatelessWidget {
  const ComprobanteMiniatura({super.key, required this.comprobante});

  final ComprobantePedido comprobante;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final color = comprobante.rechazado ? AppTheme.errorColor : (comprobante.aprobado ? AppTheme.successColor : AppTheme.infoColor);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: comprobante.imagen == null ? null : () => verComprobante(context, comprobante.imagen!),
            child: ImagenRed(url: comprobante.imagen, ancho: 64, alto: 84, radio: 10, icono: Icons.receipt_long_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comprobante.aprobado ? 'Pago recibido' : (comprobante.rechazado ? 'No llegó' : 'Por revisar'),
                  style: tema.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
                if (comprobante.referencia != null) Text('Referencia: ${comprobante.referencia}', style: tema.bodySmall),
                if (comprobante.fecha != null) Text('Enviado ${Formato.fechaRelativa(comprobante.fecha!)}', style: tema.bodySmall),
                if (comprobante.rechazado && comprobante.motivo != null) Text('Motivo: ${comprobante.motivo}', style: tema.bodySmall?.copyWith(color: color)),
                if (comprobante.imagen != null) Text('Toca la foto para verla en grande', style: tema.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
