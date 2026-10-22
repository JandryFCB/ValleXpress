import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/suscripcion.dart';
import 'ui/ui.dart';

/// A dónde transferir: banco, tipo, número, titular y cédula/RUC, con botones para copiar. La usan la suscripción
/// (cuentas de ValleXpress) y el pago de un pedido por transferencia (cuentas del negocio).
class TarjetaCuentaBanco extends StatelessWidget {
  const TarjetaCuentaBanco({super.key, required this.cuenta, this.sinCuenta = 'ValleXpress todavía no publicó su cuenta para transferir: escríbenos a soporte'});

  final CuentaCobro cuenta;

  /// Lo que se muestra si la cuenta está incompleta
  final String sinCuenta;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    if (!cuenta.completa) return InsigniaValle(sinCuenta, color: AppTheme.infoColor, icono: Icons.info_outline);
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

/// Hoja para agregar ([actual] null) o editar una cuenta bancaria. Devuelve la cuenta o null si se cerró.
Future<CuentaCobro?> editarCuentaBanco(BuildContext context, {CuentaCobro? actual}) {
  final base = actual ?? const CuentaCobro();
  final banco = TextEditingController(text: base.banco);
  final numero = TextEditingController(text: base.numero);
  final titular = TextEditingController(text: base.titular);
  final identificacion = TextEditingController(text: base.identificacion);
  var tipo = base.tipo;
  return showModalBottomSheet<CuentaCobro>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setHoja) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(actual == null ? 'Nueva cuenta' : 'Editar cuenta', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            CampoValle(controller: banco, etiqueta: 'Banco o cooperativa', icono: Icons.account_balance_rounded, maxLongitud: 60, mayusculas: TextCapitalization.words),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'ahorros', label: Text('Ahorros')), ButtonSegment(value: 'corriente', label: Text('Corriente'))],
                selected: {tipo},
                onSelectionChanged: (v) => setHoja(() => tipo = v.first),
              ),
            ),
            const SizedBox(height: 12),
            CampoValle(controller: numero, etiqueta: 'Número de cuenta', icono: Icons.numbers_rounded, tipoTeclado: TextInputType.number, formateadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))], maxLongitud: 30),
            const SizedBox(height: 12),
            CampoValle(controller: titular, etiqueta: 'Titular', icono: Icons.person_outline_rounded, maxLongitud: 100, mayusculas: TextCapitalization.words),
            const SizedBox(height: 12),
            CampoValle(controller: identificacion, etiqueta: 'Cédula o RUC del titular', icono: Icons.badge_outlined, tipoTeclado: TextInputType.number, formateadores: [FilteringTextInputFormatter.digitsOnly], maxLongitud: 13),
            const SizedBox(height: 16),
            BotonValle(
              texto: 'Listo',
              icono: Icons.check_rounded,
              onPressed: () {
                final id = identificacion.text.trim();
                if (banco.text.trim().isEmpty || numero.text.trim().isEmpty || titular.text.trim().isEmpty) return mostrarError(ctx, 'Escribe el banco, el número y el titular');
                if (numero.text.trim().length < 4) return mostrarError(ctx, 'Revisa el número de cuenta');
                if (id.isNotEmpty && id.length != 10 && id.length != 13) return mostrarError(ctx, 'La cédula tiene 10 dígitos y el RUC 13');
                Navigator.pop(ctx, CuentaCobro(banco: banco.text.trim(), tipo: tipo, numero: numero.text.trim(), titular: titular.text.trim(), identificacion: id, notas: base.notas, completa: true));
              },
            ),
          ]),
        ),
      ),
    ),
  );
}
