import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/admin.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/contacto.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../repartidor/vehiculo_screen.dart';
import '../vendedor/mi_negocio_screen.dart';
import 'pedir_motivo.dart';
import 'usuarios_admin_screen.dart';

/// Gestión de negocios y repartidores: revisar los nuevos (aprobar o rechazar), suspender o reactivar, editar un
/// negocio completo (datos, horario, local, imágenes y productos) y el vehículo de un repartidor.
class AprobacionesScreen extends StatelessWidget {
  const AprobacionesScreen({super.key, this.alCambiar, this.pestanaInicial = 0, this.conAtras = false});

  /// Avisa al inicio del admin que cambió algo (para refrescar el contador de pendientes)
  final VoidCallback? alCambiar;

  /// 0 = negocios, 1 = repartidores (desde "Perfiles y permisos" se abre en la del perfil elegido)
  final int pestanaInicial;

  /// Abierta como página aparte (con flecha para volver), no como pestaña del inicio
  final bool conAtras;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: pestanaInicial,
      child: FondoValle(
        appBar: AppBar(
          title: Text(conAtras ? 'Solicitudes' : 'Gestión'),
          automaticallyImplyLeading: conAtras,
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.storefront_rounded), text: 'Negocios'),
            Tab(icon: Icon(Icons.two_wheeler_rounded), text: 'Repartidores'),
          ]),
        ),
        child: TabBarView(children: [_Lista(negocios: true, alCambiar: alCambiar), _Lista(negocios: false, alCambiar: alCambiar)]),
      ),
    );
  }
}

class _Lista extends StatefulWidget {
  const _Lista({required this.negocios, this.alCambiar});

  final bool negocios;
  final VoidCallback? alCambiar;

  @override
  State<_Lista> createState() => _ListaState();
}

class _ListaState extends State<_Lista> with AutomaticKeepAliveClientMixin {
  static const _filtros = [('pendiente', 'Pendientes'), ('aprobado', 'Aprobados'), ('suspendido', 'Suspendidos'), ('rechazado', 'Rechazados'), (null, 'Todos')];

  String? _filtro = 'pendiente';
  final _busqueda = TextEditingController();
  Timer? _espera;
  List<Object> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => (_cargando = _items.isEmpty, _error = null));
    try {
      final List<Object> items = widget.negocios
          ? (await AdminService.negocios(aprobacion: _filtro, busqueda: _busqueda.text)).items
          : (await AdminService.repartidores(aprobacion: _filtro, busqueda: _busqueda.text)).items;
      if (mounted) setState(() => (_items = items, _cargando = false));
    } catch (e) {
      if (mounted) setState(() => (_error = textoDeError(e), _cargando = false));
    }
  }

  void _buscar(String _) {
    setState(() {});      // muestra u oculta la X para borrar
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _cargar);
  }

  // ---------------------------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------------------------
  Future<void> _cambiarAprobacion(Object item, Aprobacion nueva) async {
    final esNegocio = item is NegocioAdmin;
    final nombre = esNegocio ? item.negocio.nombre : (item as RepartidorAdmin).nombre;
    String? motivo;
    if (nueva == Aprobacion.rechazado || nueva == Aprobacion.suspendido) {
      motivo = await pedirMotivo(
        context,
        titulo: '${nueva == Aprobacion.rechazado ? 'Rechazar' : 'Suspender'} a $nombre',
        explicacion: 'Le enviaremos este motivo como aviso. ${nueva == Aprobacion.suspendido ? (esNegocio ? 'El negocio se cerrará y dejará de recibir pedidos.' : 'Quedará fuera de línea y no podrá aceptar pedidos.') : ''}',
        textoBoton: nueva == Aprobacion.rechazado ? 'Rechazar' : 'Suspender',
        sugerencias: esNegocio
            ? const ['Faltan datos del negocio', 'RUC inválido', 'Productos no permitidos', 'Quejas de los clientes']
            : const ['Documentos incompletos', 'Placa no coincide', 'Quejas de los clientes', 'Documentos vencidos'],
        minimo: 3,
      );
      if (motivo == null) return;
    }
    try {
      if (esNegocio) {
        await AdminService.aprobacionNegocio(item.negocio.id, nueva.codigo, motivo: motivo);
      } else {
        await AdminService.aprobacionRepartidor((item as RepartidorAdmin).perfil.usuario, nueva.codigo, motivo: motivo);
      }
      if (!mounted) return;
      if (nueva == Aprobacion.aprobado) Confeti.lanzar(context);
      mostrarExito(context, switch (nueva) {
        Aprobacion.aprobado => '¡$nombre aprobado! Ya le avisamos',
        Aprobacion.rechazado => 'Solicitud de $nombre rechazada',
        Aprobacion.suspendido => '$nombre suspendido',
        Aprobacion.pendiente => '$nombre volvió a revisión',
      });
      widget.alCambiar?.call();
      _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _gestionarNegocio(NegocioAdmin n) async {
    await CatalogoService.gestionarComoAdmin(n.negocio.id, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MiNegocioScreen())));
    if (mounted) _cargar();
  }

  Future<void> _editarVehiculo(RepartidorAdmin r) async {
    final cambio = await Navigator.push(context, MaterialPageRoute(builder: (_) => VehiculoScreen(actual: r.perfil, deUsuario: r.perfil.usuario)));
    if (cambio != null && mounted) _cargar();
  }

  Future<void> _verCuenta(String usuario) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => UsuarioAdminScreen(usuario: usuario)));
    if (mounted) _cargar();
  }

  /// Hoja con todo lo que se puede hacer con un negocio o un repartidor
  Future<void> _acciones(Object item) async {
    final esNegocio = item is NegocioAdmin;
    final a = esNegocio ? item.aprobacion : (item as RepartidorAdmin).aprobacion;
    final contacto = esNegocio ? item.dueno : (item as RepartidorAdmin).contacto;
    final elegida = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        Widget opcion(String clave, IconData icono, String texto, {Color? color, String? detalle}) => ListTile(
              leading: Icon(icono, color: color),
              title: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              subtitle: detalle == null ? null : Text(detalle),
              onTap: () => Navigator.pop(ctx, clave),
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: esNegocio ? _CabeceraNegocio(n: item) : _CabeceraRepartidor(r: item as RepartidorAdmin),
                ),
                const Divider(),
                if (a != Aprobacion.aprobado) opcion('aprobar', Icons.verified_rounded, a == Aprobacion.pendiente ? 'Aprobar' : 'Reactivar (aprobar)', color: AppTheme.successColor),
                if (a == Aprobacion.pendiente) opcion('rechazar', Icons.block_rounded, 'Rechazar solicitud', color: AppTheme.errorColor),
                if (a == Aprobacion.aprobado) opcion('suspender', Icons.pause_circle_rounded, 'Suspender', color: AppTheme.errorColor, detalle: esNegocio ? 'Se cierra y deja de recibir pedidos' : 'Queda fuera de línea'),
                if (esNegocio) opcion('gestionar', Icons.edit_rounded, 'Editar negocio', detalle: 'Datos, horario, ubicación, logo, portada y productos'),
                if (!esNegocio) opcion('vehiculo', Icons.two_wheeler_rounded, 'Editar vehículo', detalle: 'Tipo, placa y color'),
                if (contacto != null) opcion('cuenta', Icons.manage_accounts_rounded, esNegocio ? 'Cuenta del dueño' : 'Cuenta del repartidor', detalle: 'Datos, contraseña, foto, bloquear o dar de baja'),
                if (contacto?.telefono != null) opcion('llamar', Icons.call_rounded, 'Llamar', detalle: Formato.telefono(contacto!.telefono!)),
              ],
            ),
          ),
        );
      },
    );
    if (elegida == null || !mounted) return;
    switch (elegida) {
      case 'aprobar':
        await _cambiarAprobacion(item, Aprobacion.aprobado);
      case 'rechazar':
        await _cambiarAprobacion(item, Aprobacion.rechazado);
      case 'suspender':
        await _cambiarAprobacion(item, Aprobacion.suspendido);
      case 'gestionar':
        await _gestionarNegocio(item as NegocioAdmin);
      case 'vehiculo':
        await _editarVehiculo(item as RepartidorAdmin);
      case 'cuenta':
        await _verCuenta(contacto!.usuario);
      case 'llamar':
        await llamar(context, contacto!.telefono!);
    }
  }

  // ---------------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _busqueda,
            onChanged: _buscar,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: widget.negocios ? 'Buscar negocio por nombre' : 'Buscar por usuario o placa',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _busqueda.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () {
                        _busqueda.clear();
                        _cargar();
                      }),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              for (final (valor, texto) in _filtros)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(texto),
                    selected: _filtro == valor,
                    onSelected: (_) {
                      setState(() => (_filtro = valor, _items = []));
                      _cargar();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _contenido()),
      ],
    );
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 4);
    if (_error != null && _items.isEmpty) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar la lista', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_items.isEmpty) {
      return EstadoVacio(
        icono: _filtro == 'pendiente' ? Icons.celebration_rounded : (widget.negocios ? Icons.storefront_outlined : Icons.two_wheeler_outlined),
        titulo: _filtro == 'pendiente' ? '¡Todo al día!' : 'No hay resultados',
        mensaje: _filtro == 'pendiente' ? 'No hay ${widget.negocios ? 'negocios' : 'repartidores'} esperando revisión' : 'Prueba con otro filtro o búsqueda',
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final item = _items[i];
          final pendiente = (item is NegocioAdmin ? item.aprobacion : (item as RepartidorAdmin).aprobacion) == Aprobacion.pendiente;
          return Aparecer(
            key: ValueKey(item is NegocioAdmin ? 'n${item.negocio.id}' : 'r${(item as RepartidorAdmin).perfil.usuario}'),
            indice: i,
            child: TarjetaValle(
              onTap: () => _acciones(item),
              colorBorde: pendiente ? AppTheme.warningColor.withValues(alpha: 0.6) : null,
              child: Column(
                children: [
                  item is NegocioAdmin ? _CabeceraNegocio(n: item) : _CabeceraRepartidor(r: item as RepartidorAdmin),
                  if (pendiente) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: BotonValle(texto: 'Rechazar', icono: Icons.close_rounded, tipo: TipoBoton.secundario, onPressed: () => _cambiarAprobacion(item, Aprobacion.rechazado))),
                        const SizedBox(width: 10),
                        Expanded(child: BotonValle(texto: 'Aprobar', icono: Icons.check_rounded, onPressed: () => _cambiarAprobacion(item, Aprobacion.aprobado))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CabeceraNegocio extends StatelessWidget {
  const _CabeceraNegocio({required this.n});

  final NegocioAdmin n;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final negocio = n.negocio;
    return Row(
      children: [
        ImagenRed(url: negocio.logo, ancho: 56, alto: 56, radio: 16, icono: negocio.categoria.icono),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(negocio.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${negocio.categoria.descripcion} · ${n.dueno?.nombreCompleto ?? 'Sin dueño'}', style: tema.bodySmall?.copyWith(color: c.textoSuave), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                InsigniaValle(n.aprobacion.etiqueta, color: n.aprobacion.color, icono: n.aprobacion.icono),
                if (n.aprobacion == Aprobacion.aprobado)
                  InsigniaValle(negocio.abierto ? 'Abierto' : 'Cerrado', color: negocio.abierto ? AppTheme.successColor : c.textoSuave, icono: negocio.abierto ? Icons.circle : Icons.nightlight_round),
                if (negocio.numeroCalificaciones > 0) InsigniaValle('${negocio.calificacion.toStringAsFixed(1)} ★', color: AppTheme.accentColor),
              ]),
            ],
          ),
        ),
        Icon(Icons.more_vert_rounded, color: c.textoSuave),
      ],
    );
  }
}

class _CabeceraRepartidor extends StatelessWidget {
  const _CabeceraRepartidor({required this.r});

  final RepartidorAdmin r;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final p = r.perfil;
    return Row(
      children: [
        Stack(
          children: [
            AvatarValle(nombre: r.contacto?.nombre ?? p.usuario, apellido: r.contacto?.apellido, tamano: 56, color: AppTheme.repartidorColor),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: c.tarjeta, shape: BoxShape.circle),
                child: Icon(p.vehiculo.icono, size: 16, color: AppTheme.repartidorColor),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                [p.vehiculo.etiqueta, if (p.color != null && p.color!.isNotEmpty) p.color!, if (p.placa != null) p.placa!].join(' · '),
                style: tema.bodySmall?.copyWith(color: c.textoSuave),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                InsigniaValle(r.aprobacion.etiqueta, color: r.aprobacion.color, icono: r.aprobacion.icono),
                if (p.disponible) const InsigniaValle('En línea', color: AppTheme.successColor, icono: Icons.circle),
                InsigniaValle(p.numeroEntregas == 1 ? '1 entrega' : '${p.numeroEntregas} entregas', color: AppTheme.infoColor),
                if (p.numeroCalificaciones > 0) InsigniaValle('${p.calificacion.toStringAsFixed(1)} ★', color: AppTheme.accentColor),
              ]),
            ],
          ),
        ),
        Icon(Icons.more_vert_rounded, color: c.textoSuave),
      ],
    );
  }
}
