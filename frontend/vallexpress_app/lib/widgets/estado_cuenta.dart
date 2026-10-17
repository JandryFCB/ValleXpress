import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/liquidacion.dart';
import '../utils/formato.dart';
import 'ui/ui.dart';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String _dia(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Estado de cuenta de un negocio con ValleXpress: lo que debe, si está bloqueado, a dónde transferir y sus
/// semanas. El vendedor lo ve como información; el administrador además registra pagos ([onPagar]).
class EstadoCuentaVista extends StatelessWidget {
  const EstadoCuentaVista({super.key, required this.cuenta, this.onPagar, this.paraAdmin = false});

  final EstadoDeCuenta cuenta;
  final void Function(SemanaLiquidacion semana)? onPagar;
  final bool paraAdmin;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final debe = cuenta.saldoPendiente > 0;
    final color = cuenta.bloqueado ? AppTheme.errorColor : (debe ? AppTheme.warningColor : AppTheme.successColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Saldo
        TarjetaValle(
          color: color.withValues(alpha: 0.1),
          colorBorde: color.withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(debe ? (paraAdmin ? 'Debe a ValleXpress' : 'Por pagar a ValleXpress') : 'Estás al día', style: tema.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              DineroAnimado(cuenta.saldoPendiente, estilo: tema.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                cuenta.bloqueado
                    ? (paraAdmin
                        ? 'Tiene una semana vencida: no está recibiendo pedidos hasta que pague'
                        : 'Tienes una semana vencida: no estás recibiendo pedidos. Paga y avísanos para reactivarte')
                    : debe
                        ? 'La comisión de cada semana se paga dentro de ${cuenta.diasGracia} días después de que termina'
                        : 'No hay comisiones pendientes',
                style: tema.bodySmall,
              ),
            ],
          ),
        ),
        // A dónde transferir
        if (!paraAdmin && cuenta.cuenta.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          TarjetaValle(
            onTap: () {
              Clipboard.setData(ClipboardData(text: cuenta.cuenta));
              mostrarMensaje(context, 'Copiamos los datos de la cuenta');
            },
            child: Row(
              children: [
                Icon(Icons.account_balance_rounded, color: c.primario),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transfiere a', style: tema.labelMedium?.copyWith(color: c.textoSuave)),
                      Text(cuenta.cuenta, style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Icon(Icons.copy_rounded, size: 18, color: c.textoSuave),
              ],
            ),
          ),
        ],
        EncabezadoSeccion('Semanas', subtitulo: paraAdmin ? 'Comisión de los pedidos entregados' : 'Lo que vendiste y la comisión de ValleXpress'),
        if (cuenta.semanas.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: EstadoVacio(icono: Icons.receipt_long_outlined, titulo: 'Aún no hay ventas', mensaje: 'Cuando entregues pedidos, verás aquí cada semana.'))
        else
          for (final (i, s) in cuenta.semanas.indexed)
            Aparecer(indice: i, child: _TarjetaSemana(s: s, onPagar: onPagar == null || !s.porPagar ? null : () => onPagar!(s))),
      ],
    );
  }
}

class _TarjetaSemana extends StatelessWidget {
  const _TarjetaSemana({required this.s, this.onPagar});

  final SemanaLiquidacion s;
  final VoidCallback? onPagar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    Widget linea(String t, String v, {bool fuerte = false}) => Row(children: [
          Expanded(child: Text(t, style: fuerte ? tema.bodyMedium?.copyWith(fontWeight: FontWeight.w800) : tema.bodySmall?.copyWith(color: c.textoSuave))),
          Text(v, style: fuerte ? tema.bodyMedium?.copyWith(fontWeight: FontWeight.w800) : tema.bodySmall),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaValle(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('${_dia(s.semana)} – ${_dia(s.hasta)}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              InsigniaValle(s.estado.etiqueta, color: s.estado.color, icono: s.estado.icono),
            ]),
            const SizedBox(height: 8),
            linea('${s.pedidos} ${s.pedidos == 1 ? 'pedido' : 'pedidos'} · vendido', Formato.dinero(s.ventas)),
            linea('Comisión ValleXpress', Formato.dinero(s.comision), fuerte: true),
            linea('El negocio recibió', Formato.dinero(s.recibeNegocio)),
            if (s.porPagar && s.vence != null) ...[
              const SizedBox(height: 6),
              Text(s.estado == EstadoSemana.vencida ? 'Venció el ${_dia(s.vence!)}' : 'Paga hasta el ${_dia(s.vence!)}', style: tema.bodySmall?.copyWith(color: s.estado.color, fontWeight: FontWeight.w700)),
            ],
            if (s.estado == EstadoSemana.pagada && s.fechaPago != null) ...[
              const SizedBox(height: 6),
              Text('Pagada el ${_dia(s.fechaPago!.toLocal())}${s.referencia != null ? ' · ${s.referencia}' : ''}', style: tema.bodySmall?.copyWith(color: AppTheme.successColor)),
            ],
            if (onPagar != null) ...[
              const SizedBox(height: 10),
              BotonValle(texto: 'Registrar pago', icono: Icons.check_rounded, tipo: TipoBoton.secundario, onPressed: onPagar),
            ],
          ],
        ),
      ),
    );
  }
}
