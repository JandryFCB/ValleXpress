import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/liquidacion.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../utils/formato.dart';
import '../../widgets/estado_cuenta.dart';
import '../../widgets/ui/ui.dart';
import 'pedir_motivo.dart';

/// Cobros a negocios: quién debe la comisión de semanas ya cerradas, cuánto y si ya dejó de recibir pedidos.
/// Abajo, la cuenta donde transfieren y los días de gracia. Tocar un negocio abre sus semanas para registrar pagos.
class CobrosScreen extends StatefulWidget {
  const CobrosScreen({super.key});

  @override
  State<CobrosScreen> createState() => _CobrosScreenState();
}

class _CobrosScreenState extends State<CobrosScreen> {
  List<DeudaNegocio>? _pendientes;
  final _banco = TextEditingController();
  final _numero = TextEditingController();
  final _titular = TextEditingController();
  final _identificacion = TextEditingController();
  String _tipo = 'ahorros';
  final _dias = TextEditingController();
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_banco, _numero, _titular, _identificacion, _dias]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await AdminService.liquidaciones();
      if (!mounted) return;
      setState(() => (_pendientes = r.pendientes, _error = null));
      _banco.text = r.cuenta.banco;
      _numero.text = r.cuenta.numero;
      _titular.text = r.cuenta.titular;
      _identificacion.text = r.cuenta.identificacion;
      setState(() => _tipo = r.cuenta.tipo);
      _dias.text = '${r.diasGracia}';
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _guardarConfig() async {
    final dias = int.tryParse(_dias.text.trim());
    if (dias == null || dias < 0 || dias > 60) return mostrarError(context, 'Los días de gracia van de 0 a 60');
    final id = _identificacion.text.trim();
    if (id.isNotEmpty && id.length != 10 && id.length != 13) return mostrarError(context, 'La cédula tiene 10 dígitos y el RUC 13');
    setState(() => _guardando = true);
    try {
      await AdminService.guardarConfigCobro(
        diasGracia: dias,
        cuenta: {'banco': _banco.text.trim(), 'tipo': _tipo, 'numero': _numero.text.trim(), 'titular': _titular.text.trim(), 'identificacion': id},
      );
      if (mounted) mostrarExito(context, 'Guardado');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = _pendientes;
    final total = (p ?? []).fold(0.0, (s, d) => s + d.saldo);

    return FondoValle(
      appBar: AppBar(title: const Text('Cobros a negocios')),
      child: p == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar los cobros', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TarjetaValle(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    child: Row(children: [
                      const Icon(Icons.savings_rounded, color: AppTheme.accentColor),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Por cobrar (semanas cerradas)', style: tema.titleSmall)),
                      DineroAnimado(total, estilo: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const EncabezadoSeccion('Negocios que deben'),
                  if (p.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: EstadoVacio(icono: Icons.verified_rounded, titulo: 'Todos al día', mensaje: 'Ningún negocio debe comisiones de semanas cerradas.'))
                  else
                    for (final (i, d) in p.indexed)
                      Aparecer(
                        indice: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TarjetaValle(
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => CuentaNegocioScreen(negocioId: d.negocioId, nombre: d.nombre)));
                              _cargar();
                            },
                            child: Row(children: [
                              Icon(d.bloqueado ? Icons.block_rounded : Icons.storefront_rounded, color: d.bloqueado ? AppTheme.errorColor : c.primario),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(d.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  Text(
                                    '${d.semanas} ${d.semanas == 1 ? 'semana' : 'semanas'}${d.bloqueado ? ' · sin recibir pedidos' : ''}',
                                    style: tema.bodySmall?.copyWith(color: d.bloqueado ? AppTheme.errorColor : c.textoSuave),
                                  ),
                                  if (d.porRevisar > 0) ...[
                                    const SizedBox(height: 4),
                                    InsigniaValle(d.porRevisar == 1 ? '1 comprobante por revisar' : '${d.porRevisar} comprobantes por revisar', color: AppTheme.infoColor, icono: Icons.receipt_long_rounded),
                                  ],
                                ]),
                              ),
                              Text(Formato.dinero(d.saldo), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              const Icon(Icons.chevron_right_rounded),
                            ]),
                          ),
                        ),
                      ),
                  const EncabezadoSeccion('Cómo cobras', subtitulo: 'Los negocios ven estos datos en "Mis cuentas"'),
                  TarjetaValle(
                    child: Column(children: [
                      CampoValle(controller: _banco, etiqueta: 'Banco', icono: Icons.account_balance_rounded, maxLongitud: 60, mayusculas: TextCapitalization.words),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [ButtonSegment(value: 'ahorros', label: Text('Ahorros')), ButtonSegment(value: 'corriente', label: Text('Corriente'))],
                          selected: {_tipo},
                          onSelectionChanged: (v) => setState(() => _tipo = v.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CampoValle(controller: _numero, etiqueta: 'Número de cuenta', icono: Icons.numbers_rounded, tipoTeclado: TextInputType.number, formateadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))], maxLongitud: 30),
                      const SizedBox(height: 12),
                      CampoValle(controller: _titular, etiqueta: 'Titular', icono: Icons.person_outline_rounded, maxLongitud: 100, mayusculas: TextCapitalization.words),
                      const SizedBox(height: 12),
                      CampoValle(controller: _identificacion, etiqueta: 'Cédula o RUC del titular', icono: Icons.badge_outlined, tipoTeclado: TextInputType.number, formateadores: [FilteringTextInputFormatter.digitsOnly], maxLongitud: 13),
                      const SizedBox(height: 12),
                      CampoValle(controller: _dias, etiqueta: 'Días para pagar después de cada semana', icono: Icons.event_available_rounded, tipoTeclado: TextInputType.number, formateadores: [FilteringTextInputFormatter.digitsOnly], maxLongitud: 2),
                      const SizedBox(height: 6),
                      Text('Pasado ese plazo sin pagar, el negocio deja de recibir pedidos hasta ponerse al día.', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                      const SizedBox(height: 12),
                      BotonValle(texto: 'Guardar', icono: Icons.check_rounded, tipo: TipoBoton.secundario, cargando: _guardando, onPressed: _guardarConfig),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Las semanas de un negocio, para registrar sus pagos
class CuentaNegocioScreen extends StatefulWidget {
  const CuentaNegocioScreen({super.key, required this.negocioId, required this.nombre});

  final int negocioId;
  final String nombre;

  @override
  State<CuentaNegocioScreen> createState() => _CuentaNegocioScreenState();
}

class _CuentaNegocioScreenState extends State<CuentaNegocioScreen> {
  EstadoDeCuenta? _cuenta;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final c = await AdminService.liquidacionesDe(widget.negocioId);
      if (mounted) setState(() => (_cuenta = c, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _pagar(SemanaLiquidacion s) async {
    final referencia = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Registrar el pago de ${Formato.dinero(s.comision)}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Confirma que recibiste la transferencia o el efectivo de esta semana.'),
          const SizedBox(height: 12),
          TextField(controller: referencia, maxLength: 100, decoration: const InputDecoration(labelText: 'Referencia (opcional)', hintText: 'Nº de transferencia o recibo')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar pago')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final c = await AdminService.registrarPago(widget.negocioId, s.codigoSemana, referencia: referencia.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarExito(context, c.bloqueado ? 'Pago registrado. Aún tiene otra semana vencida' : 'Pago registrado y le avisamos al negocio');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _aprobar(ComprobantePago comp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Aprobar el comprobante?'),
        content: const Text('Confirma que el dinero llegó a tu cuenta. La semana queda pagada y le avisamos al negocio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprobar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final c = await AdminService.aprobarComprobante(comp.id);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarExito(context, 'Pago aprobado y le avisamos al negocio');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _rechazar(ComprobantePago comp) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Rechazar comprobante',
      explicacion: 'El negocio verá el motivo y podrá subir otro.',
      textoBoton: 'Rechazar',
      sugerencias: const ['La foto no se lee', 'El monto no coincide', 'No encontramos la transferencia', 'Es de otra semana'],
    );
    if (motivo == null) return;
    try {
      final c = await AdminService.rechazarComprobante(comp.id, motivo);
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarMensaje(context, 'Comprobante rechazado: le avisamos al negocio');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(
      appBar: AppBar(title: Text(widget.nombre)),
      child: _cuenta == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el estado de cuenta', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [EstadoCuentaVista(cuenta: _cuenta!, paraAdmin: true, onPagar: _pagar, onAprobar: _aprobar, onRechazar: _rechazar)],
              ),
            ),
    );
  }
}
