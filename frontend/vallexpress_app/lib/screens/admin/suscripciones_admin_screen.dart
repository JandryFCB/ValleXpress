import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/suscripcion.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../utils/formato.dart';
import '../../widgets/estado_cuenta.dart';
import '../../widgets/ui/ui.dart';
import 'pedir_motivo.dart';

const _sugerenciasRechazo = ['La foto no se lee', 'El monto no coincide', 'No encontramos la transferencia', 'Es de otro mes'];

/// Suscripciones: los comprobantes que esperan tu revisión, quiénes pagan (vendedores y repartidores) y cómo van, y
/// la configuración del cobro (cuotas, día límite, desde qué mes se cobra y la cuenta donde transfieren).
class SuscripcionesAdminScreen extends StatefulWidget {
  const SuscripcionesAdminScreen({super.key});

  @override
  State<SuscripcionesAdminScreen> createState() => _SuscripcionesAdminScreenState();
}

class _SuscripcionesAdminScreenState extends State<SuscripcionesAdminScreen> {
  List<ComprobantePorRevisar>? _comprobantes;
  List<Suscriptor> _suscriptores = [];
  final _cuotaVendedor = TextEditingController();
  final _cuotaRepartidor = TextEditingController();
  final _dia = TextEditingController();
  final _inicio = TextEditingController();
  List<CuentaCobro> _cuentas = []; // a dónde transfieren vendedores y repartidores (pueden ser varias)
  String? _error;
  bool _guardando = false;
  int? _revisando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_cuotaVendedor, _cuotaRepartidor, _dia, _inicio]) {
      c.dispose();
    }
    super.dispose();
  }

  String _dinero(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  Future<void> _cargar() async {
    try {
      final r = await AdminService.suscripciones();
      if (!mounted) return;
      setState(() => (_comprobantes = r.comprobantes, _suscriptores = r.suscriptores, _error = null, _cuentas = r.config.cuentas));
      _cuotaVendedor.text = _dinero(r.config.cuotaVendedor);
      _cuotaRepartidor.text = _dinero(r.config.cuotaRepartidor);
      _dia.text = '${r.config.diasGracia}';
      _inicio.text = r.config.inicio.length >= 7 ? r.config.inicio.substring(0, 7) : r.config.inicio;
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _guardarConfig() async {
    final cv = double.tryParse(_cuotaVendedor.text.trim().replaceAll(',', '.'));
    final cr = double.tryParse(_cuotaRepartidor.text.trim().replaceAll(',', '.'));
    final dia = int.tryParse(_dia.text.trim());
    final inicio = _inicio.text.trim();
    if (cv == null || cv < 0 || cv > 500 || cr == null || cr < 0 || cr > 500) return mostrarError(context, 'Las cuotas van de \$0 a \$500');
    if (dia == null || dia < 1 || dia > 28) return mostrarError(context, 'El día límite para pagar va del 1 al 28');
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(inicio)) return mostrarError(context, 'Escribe desde qué mes se cobra así: 2026-11');
    setState(() => _guardando = true);
    try {
      await AdminService.guardarConfigSuscripcion({
        'cuotaVendedor': cv,
        'cuotaRepartidor': cr,
        'diasGracia': dia,
        'inicio': inicio,
        'cuentas': [for (final c in _cuentas) c.aJson()],
      });
      if (mounted) mostrarExito(context, 'Guardado');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // Agregar (indice null) o editar una cuenta bancaria. Se guarda con el botón "Guardar" de abajo.
  Future<void> _editarCuenta(int? indice) async {
    final actual = indice == null ? const CuentaCobro() : _cuentas[indice];
    final banco = TextEditingController(text: actual.banco);
    final numero = TextEditingController(text: actual.numero);
    final titular = TextEditingController(text: actual.titular);
    final identificacion = TextEditingController(text: actual.identificacion);
    var tipo = actual.tipo;
    final lista = await showModalBottomSheet<CuentaCobro>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setHoja) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(indice == null ? 'Nueva cuenta' : 'Editar cuenta', style: Theme.of(ctx).textTheme.titleLarge),
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
                  if (id.isNotEmpty && id.length != 10 && id.length != 13) return mostrarError(ctx, 'La cédula tiene 10 dígitos y el RUC 13');
                  Navigator.pop(ctx, CuentaCobro(banco: banco.text.trim(), tipo: tipo, numero: numero.text.trim(), titular: titular.text.trim(), identificacion: id, notas: actual.notas, completa: true));
                },
              ),
            ]),
          ),
        ),
      ),
    );
    if (lista == null || !mounted) return;
    setState(() => _cuentas = indice == null ? [..._cuentas, lista] : [for (final (i, c) in _cuentas.indexed) i == indice ? lista : c]);
    mostrarMensaje(context, 'Toca "Guardar" para publicarla');
  }

  Future<void> _aprobar(ComprobantePorRevisar c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Aprobar ${Formato.dinero(c.monto)}?'),
        content: Text('Confirma que el dinero de ${c.nombre} (${c.nombreMes}) llegó a tu cuenta. Le avisamos que quedó pagado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprobar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _revisando = c.id);
    try {
      await AdminService.aprobarComprobante(c.id);
      HapticFeedback.mediumImpact();
      if (mounted) mostrarExito(context, 'Pago aprobado y le avisamos');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _revisando = null);
    }
  }

  Future<void> _rechazar(ComprobantePorRevisar c) async {
    final motivo = await pedirMotivo(context, titulo: 'Rechazar comprobante', explicacion: '${c.nombre} verá el motivo y podrá subir otro.', textoBoton: 'Rechazar', sugerencias: _sugerenciasRechazo);
    if (motivo == null) return;
    setState(() => _revisando = c.id);
    try {
      await AdminService.rechazarComprobante(c.id, motivo);
      if (mounted) mostrarMensaje(context, 'Comprobante rechazado: le avisamos');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _revisando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final comps = _comprobantes;
    final porCobrar = _suscriptores.fold(0.0, (s, x) => s + x.saldoPendiente);
    final vencidos = _suscriptores.where((s) => s.bloqueado).length;

    return FondoValle(
      appBar: AppBar(title: const Text('Suscripciones')),
      child: comps == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar las suscripciones', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
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
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Por cobrar', style: tema.titleSmall),
                          Text('${_suscriptores.length} pagan · $vencidos ${vencidos == 1 ? 'vencido' : 'vencidos'}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                        ]),
                      ),
                      DineroAnimado(porCobrar, estilo: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),

                  EncabezadoSeccion('Comprobantes por revisar', subtitulo: comps.isEmpty ? null : 'Confirma en tu banco que llegó el dinero antes de aprobar'),
                  if (comps.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: InsigniaValle('No hay comprobantes esperando revisión', color: AppTheme.successColor, icono: Icons.verified_rounded))
                  else
                    for (final (i, k) in comps.indexed)
                      Aparecer(
                        indice: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TarjetaValle(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                GestureDetector(
                                  onTap: k.imagen == null ? null : () => verComprobante(context, k.imagen!),
                                  child: ImagenRed(url: k.imagen, ancho: 64, alto: 84, radio: 10, icono: Icons.receipt_long_rounded),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(k.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                    Text('${k.tipo == 'vendedor' ? 'Vendedor' : 'Repartidor'} · ${k.nombreMes}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                                    const SizedBox(height: 4),
                                    Text(Formato.dinero(k.monto), style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                    if (k.referencia != null) Text('Referencia: ${k.referencia}', style: tema.bodySmall),
                                    Text('Toca la foto para verla en grande', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                                  ]),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(child: BotonValle(texto: 'Rechazar', tipo: TipoBoton.secundario, onPressed: _revisando == null ? () => _rechazar(k) : null)),
                                const SizedBox(width: 10),
                                Expanded(child: BotonValle(texto: 'Aprobar', icono: Icons.check_rounded, cargando: _revisando == k.id, onPressed: _revisando == null ? () => _aprobar(k) : null)),
                              ]),
                            ]),
                          ),
                        ),
                      ),

                  const EncabezadoSeccion('Quiénes pagan', subtitulo: 'Vendedores y repartidores aprobados'),
                  if (_suscriptores.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: EstadoVacio(icono: Icons.groups_rounded, titulo: 'Todavía nadie paga', mensaje: 'Cuando apruebes vendedores o repartidores aparecerán aquí.'))
                  else
                    for (final s in _suscriptores)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TarjetaValle(
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => SuscripcionUsuarioScreen(usuario: s.usuario, nombre: s.nombre)));
                            _cargar();
                          },
                          child: Row(children: [
                            Icon(s.tipo == 'vendedor' ? Icons.storefront_rounded : Icons.delivery_dining_rounded, color: s.bloqueado ? AppTheme.errorColor : c.primario),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text('${s.tipo == 'vendedor' ? 'Vendedor' : 'Repartidor'} · ${Formato.dinero(s.cuota)} al mes', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                              ]),
                            ),
                            InsigniaValle(
                              s.enRevision > 0 ? 'Revisar' : s.bloqueado ? 'Vencida' : s.saldoPendiente > 0 ? 'Por pagar' : 'Al día',
                              color: s.enRevision > 0 ? AppTheme.infoColor : s.bloqueado ? AppTheme.errorColor : s.saldoPendiente > 0 ? AppTheme.warningColor : AppTheme.successColor,
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ]),
                        ),
                      ),

                  const EncabezadoSeccion('Cómo cobras', subtitulo: 'Vendedores y repartidores ven estos datos en "Mi suscripción"'),
                  TarjetaValle(
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: CampoValle(controller: _cuotaVendedor, etiqueta: 'Cuota vendedor \$', icono: Icons.storefront_rounded, tipoTeclado: const TextInputType.numberWithOptions(decimal: true), maxLongitud: 6)),
                        const SizedBox(width: 10),
                        Expanded(child: CampoValle(controller: _cuotaRepartidor, etiqueta: 'Cuota repartidor \$', icono: Icons.delivery_dining_rounded, tipoTeclado: const TextInputType.numberWithOptions(decimal: true), maxLongitud: 6)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: CampoValle(controller: _dia, etiqueta: 'Pagan hasta el día', icono: Icons.event_available_rounded, tipoTeclado: TextInputType.number, formateadores: [FilteringTextInputFormatter.digitsOnly], maxLongitud: 2)),
                        const SizedBox(width: 10),
                        Expanded(child: CampoValle(controller: _inicio, etiqueta: 'Cobrar desde (AAAA-MM)', icono: Icons.calendar_month_rounded, tipoTeclado: TextInputType.datetime, maxLongitud: 7)),
                      ]),
                      const SizedBox(height: 6),
                      Text('El mes en que se aprueba a alguien es gratis. Pasado el día límite sin pagar, el negocio deja de recibir pedidos y el repartidor no puede conectarse.', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                      const SizedBox(height: 16),
                      Align(alignment: Alignment.centerLeft, child: Text('Cuentas para transferir', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Pon varias si quieres (otro banco o cooperativa): cada uno transfiere a la que le quede mejor.', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                      ),
                      const SizedBox(height: 8),
                      for (final (i, cuenta) in _cuentas.indexed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_balance_rounded),
                          title: Text(cuenta.banco.isEmpty ? 'Cuenta sin banco' : cuenta.banco),
                          subtitle: Text('${cuenta.tipoTexto} ${cuenta.numero} · ${cuenta.titular}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_rounded), onPressed: () => _editarCuenta(i)),
                            IconButton(tooltip: 'Quitar', icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorColor), onPressed: () => setState(() => _cuentas = [..._cuentas]..removeAt(i))),
                          ]),
                        ),
                      if (_cuentas.length < 10)
                        BotonValle(texto: 'Agregar cuenta', icono: Icons.add_rounded, tipo: TipoBoton.texto, onPressed: () => _editarCuenta(null)),
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

/// La suscripción de un vendedor o repartidor: sus meses, para revisar comprobantes o registrar pagos en efectivo
class SuscripcionUsuarioScreen extends StatefulWidget {
  const SuscripcionUsuarioScreen({super.key, required this.usuario, required this.nombre});

  final String usuario;
  final String nombre;

  @override
  State<SuscripcionUsuarioScreen> createState() => _SuscripcionUsuarioScreenState();
}

class _SuscripcionUsuarioScreenState extends State<SuscripcionUsuarioScreen> {
  EstadoSuscripcion? _cuenta;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final c = await AdminService.suscripcionDe(widget.usuario);
      if (mounted) setState(() => (_cuenta = c, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _pagar(MesSuscripcion m) async {
    final referencia = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Registrar ${m.titulo}: ${Formato.dinero(m.monto)}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Confirma que recibiste el efectivo o la transferencia de este mes.'),
          const SizedBox(height: 12),
          TextField(controller: referencia, maxLength: 100, decoration: const InputDecoration(labelText: 'Referencia (opcional)', hintText: 'Efectivo, nº de transferencia o recibo')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar pago')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final c = await AdminService.registrarPagoSuscripcion(widget.usuario, m.mes, referencia: referencia.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarExito(context, c.bloqueado ? 'Pago registrado. Aún tiene otro mes vencido' : 'Pago registrado y le avisamos');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _aprobar(PagoSuscripcion comp) async {
    try {
      final c = await AdminService.aprobarComprobante(comp.id);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarExito(context, 'Pago aprobado y le avisamos');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _rechazar(PagoSuscripcion comp) async {
    final motivo = await pedirMotivo(context, titulo: 'Rechazar comprobante', explicacion: 'Verá el motivo y podrá subir otro.', textoBoton: 'Rechazar', sugerencias: _sugerenciasRechazo);
    if (motivo == null) return;
    try {
      final c = await AdminService.rechazarComprobante(comp.id, motivo);
      if (!mounted) return;
      setState(() => _cuenta = c);
      mostrarMensaje(context, 'Comprobante rechazado: le avisamos');
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
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar la suscripción', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [EstadoSuscripcionVista(cuenta: _cuenta!, paraAdmin: true, onPagar: _pagar, onAprobar: _aprobar, onRechazar: _rechazar)],
              ),
            ),
    );
  }
}
