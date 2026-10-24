import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/suscripcion.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../widgets/cuentas_banco.dart';
import '../../widgets/ui/ui.dart';

/// Cuentas para transferencias (vendedor): dónde le transfieren sus clientes. Sin ninguna, los clientes de este
/// negocio solo pueden pagar en efectivo. Cada cambio se guarda al momento.
class CuentasNegocioScreen extends StatefulWidget {
  const CuentasNegocioScreen({super.key});

  @override
  State<CuentasNegocioScreen> createState() => _CuentasNegocioScreenState();
}

class _CuentasNegocioScreenState extends State<CuentasNegocioScreen> {
  static const _maximo = 5;
  List<CuentaCobro>? _cuentas;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final c = await CatalogoService.cuentasNegocio();
      if (mounted) setState(() => _cuentas = c);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _guardar(List<CuentaCobro> nuevas, String mensaje) async {
    setState(() => _guardando = true);
    try {
      final c = await CatalogoService.guardarCuentasNegocio(nuevas);
      if (!mounted) return;
      setState(() => _cuentas = c);
      mostrarExito(context, mensaje);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _editar(int? indice) async {
    final lista = _cuentas ?? [];
    final cuenta = await editarCuentaBanco(context, actual: indice == null ? null : lista[indice]);
    if (cuenta == null || !mounted) return;
    await _guardar(indice == null ? [...lista, cuenta] : [for (final (i, c) in lista.indexed) i == indice ? cuenta : c], indice == null ? 'Cuenta agregada' : 'Cuenta actualizada');
  }

  Future<void> _quitar(int indice) async {
    final lista = _cuentas!;
    final ultima = lista.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Quitar la cuenta de ${lista[indice].banco}?'),
        content: Text(ultima ? 'Es tu única cuenta: tus clientes ya no podrán pagarte por transferencia, solo en efectivo.' : 'Tus clientes ya no la verán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok == true && mounted) await _guardar([...lista]..removeAt(indice), 'Cuenta quitada');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final cuentas = _cuentas;
    return FondoValle(
      anchoEscritorio: 760, // computador: una columna centrada (estirada se ve vacía)
      titulo: 'Cuentas para transferencias',
      child: _error != null
          ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tus cuentas', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
          : cuentas == null
              ? const EsqueletoLista()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    TarjetaValle(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline_rounded, color: c.primario),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cuando confirmes un pedido por transferencia, el cliente verá estas cuentas, te transferirá y subirá la foto del comprobante. '
                            'Tú revisas que te llegó y tocas "Pago recibido" para empezar a prepararlo.\n\nSin cuentas, tus clientes solo pueden pagar en efectivo.',
                            style: tema.bodySmall?.copyWith(color: c.textoSuave),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (cuentas.isEmpty)
                      EstadoVacio(
                        icono: Icons.account_balance_rounded,
                        titulo: 'Aún no tienes cuentas',
                        mensaje: 'Agrega una para que tus clientes puedan pagarte por transferencia.',
                        textoAccion: 'Agregar cuenta',
                        onAccion: _guardando ? null : () => _editar(null),
                      )
                    else ...[
                      TarjetaValle(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          for (final (i, cuenta) in cuentas.indexed) ...[
                            if (i > 0) Divider(height: 1, indent: 70, color: c.borde),
                            ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                                child: Icon(Icons.account_balance_rounded, size: 20, color: c.primario),
                              ),
                              title: Text(cuenta.banco, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              subtitle: Text('${cuenta.tipoTexto} ${cuenta.numero}\n${cuenta.titular}${cuenta.identificacion.isEmpty ? '' : ' · ${cuenta.identificacion}'}'),
                              isThreeLine: true,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_rounded), onPressed: _guardando ? null : () => _editar(i)),
                                IconButton(tooltip: 'Quitar', icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorColor), onPressed: _guardando ? null : () => _quitar(i)),
                              ]),
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (cuentas.length < _maximo)
                        BotonValle(texto: 'Agregar otra cuenta', icono: Icons.add_rounded, tipo: TipoBoton.secundario, cargando: _guardando, onPressed: () => _editar(null))
                      else
                        Text('Puedes tener hasta $_maximo cuentas.', textAlign: TextAlign.center, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                    ],
                  ],
                ),
    );
  }
}
