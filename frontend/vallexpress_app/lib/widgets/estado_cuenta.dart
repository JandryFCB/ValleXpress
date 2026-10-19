import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/suscripcion.dart';
import '../utils/formato.dart';
import 'ui/ui.dart';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String _dia(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Suscripción mensual de un vendedor o repartidor: lo que debe, si está bloqueado, a dónde transferir y sus meses.
/// El vendedor o repartidor sube el comprobante de cada mes ([onSubirComprobante]); el administrador lo revisa
/// ([onAprobar] / [onRechazar]) o registra un pago sin comprobante ([onPagar]).
class EstadoSuscripcionVista extends StatelessWidget {
  const EstadoSuscripcionVista({
    super.key,
    required this.cuenta,
    this.paraAdmin = false,
    this.onSubirComprobante,
    this.onPagar,
    this.onAprobar,
    this.onRechazar,
  });

  final EstadoSuscripcion cuenta;
  final bool paraAdmin;
  final void Function(MesSuscripcion mes)? onSubirComprobante;
  final void Function(MesSuscripcion mes)? onPagar;
  final void Function(PagoSuscripcion comprobante)? onAprobar;
  final void Function(PagoSuscripcion comprobante)? onRechazar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    if (!cuenta.aplica) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: EstadoVacio(
          icono: Icons.hourglass_empty_rounded,
          titulo: 'Aún no pagas suscripción',
          mensaje: 'La suscripción se cobra desde que aprobamos tu cuenta (el primer mes es gratis).',
        ),
      );
    }
    final debe = cuenta.saldoPendiente > 0;
    final soloRevision = !debe && cuenta.enRevision > 0;
    final color = cuenta.bloqueado
        ? AppTheme.errorColor
        : soloRevision
            ? AppTheme.infoColor
            : (debe ? AppTheme.warningColor : AppTheme.successColor);
    final quien = cuenta.tipo == 'vendedor' ? 'tus negocios no reciben pedidos' : 'no puedes conectarte ni aceptar pedidos';

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
              Text(
                cuenta.bloqueado ? 'Suscripción vencida' : soloRevision ? 'Comprobante en revisión' : debe ? 'Por pagar' : 'Estás al día',
                style: tema.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              DineroAnimado(cuenta.saldoPendiente, estilo: tema.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                cuenta.bloqueado
                    ? (paraAdmin ? 'Tiene un mes vencido: está bloqueado hasta que pague' : 'Tienes un mes vencido: $quien. Transfiere y sube el comprobante')
                    : soloRevision
                        ? (paraAdmin ? 'Envió el comprobante: revísalo abajo para aprobarlo o rechazarlo' : 'Ya enviaste el comprobante. Te avisamos apenas lo revisemos')
                        : 'Cuota de ${Formato.dinero(cuenta.cuota ?? 0)} al mes. Se paga hasta el día ${cuenta.diasGracia} de cada mes',
                style: tema.bodySmall,
              ),
            ],
          ),
        ),
        if (!paraAdmin) ...[
          const SizedBox(height: 12),
          if (cuenta.cuentas.where((x) => x.completa).isEmpty)
            const InsigniaValle('ValleXpress todavía no publicó su cuenta para transferir: escríbenos a soporte', color: AppTheme.infoColor, icono: Icons.info_outline)
          else ...[
            if (cuenta.cuentas.where((x) => x.completa).length > 1)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Transfiere a la cuenta que te quede mejor:', style: tema.titleSmall)),
            for (final c in cuenta.cuentas.where((x) => x.completa)) Padding(padding: const EdgeInsets.only(bottom: 10), child: _TarjetaCuenta(cuenta: c)),
          ],
        ],
        EncabezadoSeccion('Meses', subtitulo: paraAdmin ? null : 'El mes en que te aprobamos es gratis'),
        for (final (i, m) in cuenta.meses.indexed)
          Aparecer(
            indice: i,
            child: _TarjetaMes(
              m: m,
              paraAdmin: paraAdmin,
              onSubir: onSubirComprobante == null || !m.pagable ? null : () => onSubirComprobante!(m),
              onPagar: onPagar == null || !m.pagable ? null : () => onPagar!(m),
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

class _TarjetaMes extends StatelessWidget {
  const _TarjetaMes({required this.m, required this.paraAdmin, this.onSubir, this.onPagar, this.onAprobar, this.onRechazar});

  final MesSuscripcion m;
  final bool paraAdmin;
  final VoidCallback? onSubir;
  final VoidCallback? onPagar;
  final void Function(PagoSuscripcion comprobante)? onAprobar;
  final void Function(PagoSuscripcion comprobante)? onRechazar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final comp = m.comprobante ?? m.rechazado;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaValle(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(m.titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              Text(Formato.dinero(m.monto), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              InsigniaValle(m.estado.etiqueta, color: m.estado.color, icono: m.estado.icono),
            ]),
            if (m.estado == EstadoMes.porPagar || m.estado == EstadoMes.vencido || m.estado == EstadoMes.proximo) ...[
              const SizedBox(height: 6),
              Text(
                m.estado == EstadoMes.vencido
                    ? 'Venció el ${_dia(m.vence)}'
                    : m.estado == EstadoMes.proximo
                        ? 'Puedes adelantarlo · se paga hasta el ${_dia(m.vence)}'
                        : 'Paga hasta el ${_dia(m.vence)}',
                style: tema.bodySmall?.copyWith(color: m.estado.color, fontWeight: FontWeight.w700),
              ),
            ],
            if (m.estado == EstadoMes.pagado && m.pago != null) ...[
              const SizedBox(height: 6),
              Text(
                'Pagado${m.pago!.revisadoEn != null ? ' el ${_dia(m.pago!.revisadoEn!.toLocal())}' : ''}${m.pago!.referencia != null ? ' · ${m.pago!.referencia}' : ''}',
                style: tema.bodySmall?.copyWith(color: AppTheme.successColor),
              ),
            ],

            // Comprobante: en revisión (con la foto) o rechazado (con el motivo)
            if (comp != null && m.estado != EstadoMes.pagado) ...[
              const SizedBox(height: 10),
              _Comprobante(comp: comp),
            ],
            if (paraAdmin && m.comprobante != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: BotonValle(texto: 'Rechazar', tipo: TipoBoton.secundario, onPressed: onRechazar == null ? null : () => onRechazar!(m.comprobante!))),
                const SizedBox(width: 10),
                Expanded(child: BotonValle(texto: 'Aprobar', icono: Icons.check_rounded, onPressed: onAprobar == null ? null : () => onAprobar!(m.comprobante!))),
              ]),
            ] else if (onPagar != null) ...[
              const SizedBox(height: 10),
              BotonValle(texto: 'Registrar pago sin comprobante', icono: Icons.payments_outlined, tipo: TipoBoton.texto, onPressed: onPagar),
            ],
            if (onSubir != null) ...[
              const SizedBox(height: 10),
              BotonValle(
                texto: m.rechazado != null ? 'Subir otro comprobante' : m.estado == EstadoMes.proximo ? 'Adelantar este mes' : 'Subir comprobante de pago',
                icono: Icons.upload_file_rounded,
                tipo: m.estado == EstadoMes.proximo ? TipoBoton.secundario : TipoBoton.principal,
                onPressed: onSubir,
              ),
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

  final PagoSuscripcion comp;

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
            onTap: comp.imagen == null ? null : () => verComprobante(context, comp.imagen!),
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

/// Abre la foto de un comprobante en grande (se puede ampliar con los dedos)
void verComprobante(BuildContext context, String url) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(maxScale: 5, child: ImagenRed(url: url, radio: 12, fit: BoxFit.contain)),
      ),
    );
