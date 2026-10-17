import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/liquidacion.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../utils/formato.dart';
import '../../widgets/estado_cuenta.dart';
import '../../widgets/ui/ui.dart';

/// Cobros a negocios: quién debe la comisión de semanas ya cerradas, cuánto y si ya dejó de recibir pedidos.
/// Abajo, la cuenta donde transfieren y los días de gracia. Tocar un negocio abre sus semanas para registrar pagos.
class CobrosScreen extends StatefulWidget {
  const CobrosScreen({super.key});

  @override
  State<CobrosScreen> createState() => _CobrosScreenState();
}

class _CobrosScreenState extends State<CobrosScreen> {
  List<DeudaNegocio>? _pendientes;
  final _cuenta = TextEditingController();
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
    _cuenta.dispose();
    _dias.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await AdminService.liquidaciones();
      if (!mounted) return;
      setState(() => (_pendientes = r.pendientes, _error = null));
      _cuenta.text = r.cuenta;
      _dias.text = '${r.diasGracia}';
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _guardarConfig() async {
    final dias = int.tryParse(_dias.text.trim());
    if (dias == null || dias < 0 || dias > 60) return mostrarError(context, 'Los días de gracia van de 0 a 60');
    setState(() => _guardando = true);
    try {
      await AdminService.guardarConfigCobro(diasGracia: dias, cuenta: _cuenta.text.trim());
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
                      CampoValle(controller: _cuenta, etiqueta: 'Cuenta para transferir (banco, número, titular)', icono: Icons.account_balance_rounded, maxLineas: 2, maxLongitud: 300),
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
                children: [EstadoCuentaVista(cuenta: _cuenta!, paraAdmin: true, onPagar: _pagar)],
              ),
            ),
    );
  }
}
