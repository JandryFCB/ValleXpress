import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/liquidacion.dart';
import '../utils/formato.dart';
import 'ui/ui.dart';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String _dia(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Estado de cuenta de un negocio con ValleXpress: lo que debe, si está bloqueado, a dónde transferir y sus
/// semanas. El vendedor sube el comprobante de cada semana ([onSubirComprobante]); el administrador lo revisa
/// ([onAprobar] / [onRechazar]) o registra un pago sin comprobante ([onPagar]).
class EstadoCuentaVista extends StatelessWidget {
  const EstadoCuentaVista({
    super.key,
    required this.cuenta,
    this.paraAdmin = false,
    this.onSubirComprobante,
    this.onPagar,
    this.onAprobar,
    this.onRechazar,
  });

  final EstadoDeCuenta cuenta;
  final bool paraAdmin;
  final void Function(SemanaLiquidacion semana)? onSubirComprobante;
  final void Function(SemanaLiquidacion semana)? onPagar;
  final void Function(ComprobantePago comprobante)? onAprobar;
  final void Function(ComprobantePago comprobante)? onRechazar;

  @override
  Widget build(BuildContext context) {
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
                        : 'Tienes una semana vencida: no estás recibiendo pedidos. Transfiere y sube el comprobante')
                    : debe
                        ? 'La comisión de cada semana se paga dentro de ${cuenta.diasGracia} días después de que termina'
                        : 'No hay comisiones pendientes',
                style: tema.bodySmall,
              ),
            ],
          ),
        ),
        if (!paraAdmin) ...[const SizedBox(height: 12), _TarjetaCuenta(cuenta: cuenta.cuenta)],
        EncabezadoSeccion('Semanas', subtitulo: paraAdmin ? 'Comisión de los pedidos entregados' : 'Lo que vendiste y la comisión de ValleXpress'),
        if (cuenta.semanas.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: EstadoVacio(icono: Icons.receipt_long_outlined, titulo: 'Aún no hay ventas', mensaje: 'Cuando entregues pedidos, verás aquí cada semana.'))
        else
          for (final (i, s) in cuenta.semanas.indexed)
            Aparecer(
              indice: i,
              child: _TarjetaSemana(
                s: s,
                paraAdmin: paraAdmin,
                onSubir: onSubirComprobante == null || !s.puedeSubirComprobante ? null : () => onSubirComprobante!(s),
                onPagar: onPagar == null || !s.porPagar ? null : () => onPagar!(s),
                onAprobar: onAprobar,
                onRechazar: onRechazar,
              ),
            ),
      ],
    );
  }
}

/// A dónde transferir: banco, tipo, número, titular y cédula/RUC, con botones para copiar
class _TarjetaCuenta extends StatelessWidget {
  const _TarjetaCuenta({required this.cuenta});

  final CuentaCobro cuenta;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    if (!cuenta.completa) {
      return const InsigniaValle('ValleXpress todavía no publicó su cuenta para transferir: escríbenos a soporte', color: AppTheme.infoColor, icono: Icons.info_outline);
    }
    void copiar(String texto, String que) {
      Clipboard.setData(ClipboardData(text: texto));
      HapticFeedback.selectionClick();
      mostrarMensaje(context, 'Copiamos $que');
    }

    Widget fila(String etiqueta, String valor, {bool copiable = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 92, child: Text(etiqueta, style: tema.bodySmall?.copyWith(color: c.textoSuave))),
            Expanded(child: Text(valor, style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (copiable)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => copiar(valor, 'el número de cuenta'),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.copy_rounded, size: 18, color: c.primario)),
              ),
          ]),
        );

    return TarjetaValle(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_balance_rounded, color: c.primario),
            const SizedBox(width: 10),
            Expanded(child: Text('Transfiere a', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          fila('Banco', cuenta.banco),
          fila('Tipo', 'Cuenta de ${cuenta.tipoTexto.toLowerCase()}'),
          fila('Número', cuenta.numero, copiable: true),
          fila('Titular', cuenta.titular),
          if (cuenta.identificacion.isNotEmpty) fila('Cédula/RUC', cuenta.identificacion),
          if (cuenta.notas.isNotEmpty) ...[const SizedBox(height: 4), Text(cuenta.notas, style: tema.bodySmall?.copyWith(color: c.textoSuave))],
          const SizedBox(height: 10),
          BotonValle(texto: 'Copiar todos los datos', icono: Icons.copy_all_rounded, tipo: TipoBoton.texto, onPressed: () => copiar(cuenta.paraCopiar, 'los datos de la cuenta')),
        ],
      ),
    );
  }
}

class _TarjetaSemana extends StatelessWidget {
  const _TarjetaSemana({required this.s, required this.paraAdmin, this.onSubir, this.onPagar, this.onAprobar, this.onRechazar});

  final SemanaLiquidacion s;
  final bool paraAdmin;
  final VoidCallback? onSubir;
  final VoidCallback? onPagar;
  final void Function(ComprobantePago comprobante)? onAprobar;
  final void Function(ComprobantePago comprobante)? onRechazar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final comp = s.comprobante;
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
            if (s.porPagar && s.vence != null && s.estado != EstadoSemana.enRevision) ...[
              const SizedBox(height: 6),
              Text(s.estado == EstadoSemana.vencida ? 'Venció el ${_dia(s.vence!)}' : 'Paga hasta el ${_dia(s.vence!)}', style: tema.bodySmall?.copyWith(color: s.estado.color, fontWeight: FontWeight.w700)),
            ],
            if (s.estado == EstadoSemana.pagada && s.fechaPago != null) ...[
              const SizedBox(height: 6),
              Text('Pagada el ${_dia(s.fechaPago!.toLocal())}${s.referencia != null ? ' · ${s.referencia}' : ''}', style: tema.bodySmall?.copyWith(color: AppTheme.successColor)),
            ],

            // Comprobante: en revisión (con la foto) o rechazado (con el motivo)
            if (comp != null && (comp.enviado || comp.rechazado)) ...[
              const SizedBox(height: 10),
              _Comprobante(comp: comp),
            ],
            if (paraAdmin && comp != null && comp.enviado) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: BotonValle(texto: 'Rechazar', tipo: TipoBoton.secundario, onPressed: onRechazar == null ? null : () => onRechazar!(comp))),
                const SizedBox(width: 10),
                Expanded(child: BotonValle(texto: 'Aprobar', icono: Icons.check_rounded, onPressed: onAprobar == null ? null : () => onAprobar!(comp))),
              ]),
            ] else if (onPagar != null) ...[
              const SizedBox(height: 10),
              BotonValle(texto: 'Registrar pago sin comprobante', icono: Icons.payments_outlined, tipo: TipoBoton.texto, onPressed: onPagar),
            ],
            if (onSubir != null) ...[
              const SizedBox(height: 10),
              BotonValle(texto: comp?.rechazado == true ? 'Subir otro comprobante' : 'Subir comprobante de pago', icono: Icons.upload_file_rounded, onPressed: onSubir),
            ],
          ],
        ),
      ),
    );
  }
}

/// La foto del comprobante (tocarla la abre en grande) con su estado
class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.comp});

  final ComprobantePago comp;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final color = comp.rechazado ? AppTheme.errorColor : AppTheme.infoColor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: comp.imagen == null
                ? null
                : () => showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog(
                        insetPadding: const EdgeInsets.all(12),
                        child: InteractiveViewer(child: ImagenRed(url: comp.imagen, radio: 12, fit: BoxFit.contain)),
                      ),
                    ),
            child: ImagenRed(url: comp.imagen, ancho: 64, alto: 84, radio: 10, icono: Icons.receipt_long_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comp.rechazado ? 'Comprobante rechazado' : 'Comprobante en revisión', style: tema.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
                if (comp.referencia != null) Text('Referencia: ${comp.referencia}', style: tema.bodySmall),
                if (comp.rechazado && comp.motivoRechazo != null) Text('Motivo: ${comp.motivoRechazo}', style: tema.bodySmall?.copyWith(color: color)),
                if (comp.enviado) Text('Toca la foto para verla en grande', style: tema.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
