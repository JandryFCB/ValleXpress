import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../widgets/ui/ui.dart';
import 'aprobaciones_screen.dart';

/// Perfiles y permisos: por cada perfil (cliente, vendedor, repartidor) el administrador decide si puede crear su
/// cuenta desde la app y, para vendedor y repartidor, si nace aprobado o espera su revisión. El cliente no pasa
/// por aprobación: solo consume.
class PerfilesScreen extends StatefulWidget {
  const PerfilesScreen({super.key});

  @override
  State<PerfilesScreen> createState() => _PerfilesScreenState();
}

class _PerfilesScreenState extends State<PerfilesScreen> {
  List<PerfilPermisos>? _perfiles;
  String? _error;
  String? _guardando; // rol que se está guardando

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final p = await AdminService.perfiles();
      if (mounted) setState(() => (_perfiles = p, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _guardar(PerfilPermisos p, {bool? registroAbierto, bool? aprobacionAutomatica, bool aprobarPendientes = false}) async {
    setState(() => _guardando = p.rol);
    try {
      final r = await AdminService.cambiarPerfil(
        p.rol,
        registroAbierto: registroAbierto,
        aprobacionAutomatica: aprobacionAutomatica,
        aprobarPendientes: aprobarPendientes,
      );
      HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() => _perfiles = [for (final x in _perfiles!) x.rol == p.rol ? r.perfil : x]);
      if (r.aprobados > 0) {
        Confeti.lanzar(context);
        mostrarExito(context, r.aprobados == 1 ? 'Aprobamos 1 solicitud y ya le avisamos' : 'Aprobamos ${r.aprobados} solicitudes y ya les avisamos');
      } else {
        mostrarMensaje(context, 'Guardado');
      }
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = null);
    }
  }

  Future<void> _cambiarRegistro(PerfilPermisos p, bool abrir) async {
    if (!abrir) {
      final ok = await _confirmar(
        titulo: '¿Cerrar el registro de ${_textos(p.rol).plural}?',
        mensaje:
            'Nadie podrá crear una cuenta de ${_textos(p.rol).singular} desde la app. Las cuentas que ya existen siguen '
            'funcionando y tú puedes crear nuevas desde Usuarios.',
        boton: 'Cerrar registro',
      );
      if (ok != true) return;
    }
    await _guardar(p, registroAbierto: abrir);
  }

  Future<void> _cambiarAprobacion(PerfilPermisos p, bool automatica) async {
    if (automatica == p.aprobacionAutomatica) return;
    var aprobarPendientes = false;
    if (automatica && p.pendientes > 0) {
      // ¿Qué pasa con las que ya esperaban?
      final eleccion = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _HojaPendientes(cantidad: p.pendientes, plural: _textos(p.rol).plural),
      );
      if (eleccion == null) return;
      aprobarPendientes = eleccion;
    }
    await _guardar(p, aprobacionAutomatica: automatica, aprobarPendientes: aprobarPendientes);
  }

  Future<void> _cambiarCupo(PerfilPermisos p) async {
    final control = TextEditingController(text: '${p.cupo?.limite ?? 0}');
    final valor = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cupo de repartidores'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Hoy hay ${p.cupo?.ocupados ?? 0} repartidores aprobados. Pon 0 para no tener límite.'),
          const SizedBox(height: 12),
          TextField(controller: control, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Máximo de repartidores')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(control.text.trim())), child: const Text('Guardar')),
        ],
      ),
    );
    if (valor == null) return;
    setState(() => _guardando = p.rol);
    try {
      final r = await AdminService.cambiarPerfil(p.rol, cupo: valor);
      if (!mounted) return;
      setState(() => _perfiles = [for (final x in _perfiles!) x.rol == p.rol ? r.perfil : x]);
      mostrarMensaje(context, 'Guardado');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = null);
    }
  }

  Future<bool?> _confirmar({required String titulo, required String mensaje, required String boton}) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(boton)),
      ],
    ),
  );

  Future<void> _verPendientes(PerfilPermisos p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AprobacionesScreen(pestanaInicial: p.rol == 'repartidor' ? 1 : 0, conAtras: true)));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final perfiles = _perfiles;
    return FondoValle(
      appBar: AppBar(title: const Text('Perfiles y permisos')),
      child: perfiles == null
          ? (_error != null
                ? EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    color: AppTheme.errorColor,
                    titulo: 'No pudimos cargar los perfiles',
                    mensaje: _error,
                    textoAccion: 'Reintentar',
                    onAccion: _cargar,
                  )
                : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Decide quién puede crear su cuenta desde la app y quién necesita tu aprobación antes de empezar. '
                    'Los vendedores y repartidores atienden a tus clientes: revisarlos protege la calidad del servicio.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colores.textoSuave),
                  ),
                  const SizedBox(height: 16),
                  for (final (i, p) in perfiles.indexed) ...[
                    Aparecer(
                      indice: i,
                      child: _TarjetaPerfil(
                        perfil: p,
                        guardando: _guardando == p.rol,
                        onRegistro: (v) => _cambiarRegistro(p, v),
                        onAprobacion: (v) => _cambiarAprobacion(p, v),
                        onVerPendientes: () => _verPendientes(p),
                        onCupo: () => _cambiarCupo(p),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _TarjetaSoporte(),
                ],
              ),
            ),
    );
  }
}

/// Textos, ícono y color de cada perfil
({String titulo, String singular, String plural, IconData icono, Color color, String revisa}) _textos(String rol) => switch (rol) {
  'vendedor' => (
    titulo: 'Vendedores',
    singular: 'vendedor',
    plural: 'vendedores',
    icono: Icons.storefront_rounded,
    color: AppTheme.vendedorColor,
    revisa: 'Revisas el nombre, la categoría, el RUC y el local del negocio.',
  ),
  'repartidor' => (
    titulo: 'Repartidores',
    singular: 'repartidor',
    plural: 'repartidores',
    icono: Icons.two_wheeler_rounded,
    color: AppTheme.repartidorColor,
    revisa: 'Revisas sus datos, el vehículo y la placa.',
  ),
  _ => (titulo: 'Clientes', singular: 'cliente', plural: 'clientes', icono: Icons.shopping_bag_rounded, color: AppTheme.clienteColor, revisa: ''),
};

class _TarjetaPerfil extends StatelessWidget {
  const _TarjetaPerfil({required this.perfil, required this.guardando, required this.onRegistro, required this.onAprobacion, required this.onVerPendientes, this.onCupo});

  final PerfilPermisos perfil;
  final bool guardando;
  final ValueChanged<bool> onRegistro;
  final ValueChanged<bool> onAprobacion;
  final VoidCallback onVerPendientes;
  final VoidCallback? onCupo;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final t = _textos(perfil.rol);
    final p = perfil;

    return TarjetaValle(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado: perfil y sus cuentas
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: t.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                child: Icon(t.icono, color: t.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      '${p.cuentas} ${p.cuentas == 1 ? 'cuenta' : 'cuentas'} · ${p.activas} ${p.activas == 1 ? 'activa' : 'activas'}',
                      style: tema.bodySmall?.copyWith(color: c.textoSuave),
                    ),
                  ],
                ),
              ),
              if (guardando) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 16, color: c.borde),

          // Registro desde la app
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.registroAbierto,
            onChanged: guardando ? null : onRegistro,
            title: const Text('Registro desde la app'),
            subtitle: Text(p.registroAbierto ? 'Pueden crear su cuenta solos' : 'Cerrado: solo tú puedes crear estas cuentas (en Usuarios)'),
          ),

          // Aprobación (solo vendedor y repartidor)
          if (p.conAprobacion) ...[
            const SizedBox(height: 4),
            Text('Aprobación de cuentas nuevas', style: tema.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.fact_check_rounded), label: Text('Manual')),
                  ButtonSegment(value: true, icon: Icon(Icons.bolt_rounded), label: Text('Automática')),
                ],
                selected: {p.aprobacionAutomatica!},
                onSelectionChanged: guardando ? null : (v) => onAprobacion(v.first),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              p.aprobacionAutomatica! ? 'Empiezan a trabajar apenas se registran, sin revisión.' : 'Esperan tu revisión antes de empezar. ${t.revisa}',
              style: tema.bodySmall?.copyWith(color: c.textoSuave),
            ),
            if (p.pendientes > 0) ...[
              const SizedBox(height: 12),
              Material(
                color: AppTheme.warningColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onVerPendientes,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_top_rounded, color: AppTheme.warningColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.pendientes == 1 ? '1 solicitud espera tu revisión' : '${p.pendientes} solicitudes esperan tu revisión',
                            style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Text('Revisar'),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
          // Cupo de repartidores: cuántos aprobados puede haber a la vez
          if (p.cupo != null) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(p.cupo!.lleno ? Icons.group_off_rounded : Icons.groups_rounded, color: p.cupo!.lleno ? AppTheme.errorColor : t.color),
              title: Text(p.cupo!.limite == 0 ? 'Cupo: sin límite' : 'Cupo: ${p.cupo!.ocupados} de ${p.cupo!.limite} aprobados'),
              subtitle: Text(p.cupo!.lleno ? 'Lleno: nadie más puede registrarse como repartidor' : 'Cuando se llene, los nuevos verán cómo escribirte para la lista de espera'),
              trailing: TextButton(onPressed: guardando ? null : onCupo, child: const Text('Cambiar')),
            ),
          ],
          if (!p.conAprobacion)
            const InsigniaValle('Sin aprobación: entran directo a pedir', color: AppTheme.successColor, icono: Icons.verified_user_rounded),
        ],
      ),
    );
  }
}

/// Al pasar a automática con solicitudes esperando: ¿se aprueban también? (true = sí, false = solo las nuevas)
class _HojaPendientes extends StatelessWidget {
  const _HojaPendientes({required this.cantidad, required this.plural});

  final int cantidad;
  final String plural;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(cantidad == 1 ? 'Hay 1 solicitud esperando' : 'Hay $cantidad solicitudes esperando', style: tema.titleLarge),
            const SizedBox(height: 8),
            Text('Desde ahora los $plural nuevos se aprobarán solos. ¿Qué hacemos con los que ya estaban esperando tu revisión?', style: tema.bodyMedium),
            const SizedBox(height: 20),
            BotonValle(
              texto: cantidad == 1 ? 'Aprobarla también' : 'Aprobar las $cantidad también',
              icono: Icons.done_all_rounded,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            BotonValle(texto: 'Solo las nuevas (las reviso yo)', tipo: TipoBoton.secundario, onPressed: () => Navigator.pop(context, false)),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp de soporte: se muestra a quien no encuentra cupo (junto al correo de soporte)
class _TarjetaSoporte extends StatefulWidget {
  @override
  State<_TarjetaSoporte> createState() => _TarjetaSoporteState();
}

class _TarjetaSoporteState extends State<_TarjetaSoporte> {
  final _numero = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    AdminService.whatsappSoporte().then((n) {
      if (mounted) _numero.text = n ?? '';
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final n = _numero.text.trim();
    if (n.isNotEmpty && !RegExp(r'^09\d{8}$').hasMatch(n)) return mostrarError(context, 'Escribe un celular de 10 dígitos que empiece con 09');
    setState(() => _guardando = true);
    try {
      await AdminService.guardarWhatsappSoporte(n);
      if (mounted) mostrarMensaje(context, 'Guardado');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => TarjetaValle(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WhatsApp de soporte', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Lo ven quienes no encuentran cupo, para escribirte.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colores.textoSuave)),
          const SizedBox(height: 12),
          CampoValle(controller: _numero, etiqueta: 'Celular (09XXXXXXXX)', icono: Icons.chat_rounded, tipoTeclado: TextInputType.phone, formateadores: [FilteringTextInputFormatter.digitsOnly], maxLongitud: 10),
          const SizedBox(height: 12),
          BotonValle(texto: 'Guardar', icono: Icons.check_rounded, tipo: TipoBoton.secundario, cargando: _guardando, onPressed: _guardar),
        ]),
      );
}
