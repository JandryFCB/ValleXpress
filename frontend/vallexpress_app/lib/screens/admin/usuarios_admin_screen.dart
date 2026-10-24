import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/admin.dart';
import '../../models/negocio.dart';
import '../../models/pedido.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/contacto.dart';
import '../../utils/formato.dart';
import '../../utils/imagen.dart';
import '../../utils/validadores.dart';
import '../../widgets/ui/ui.dart';
import 'pedir_motivo.dart';

/// Usuarios: buscar cualquier cuenta, filtrar por rol y crear cuentas nuevas de cualquier rol.
class UsuariosAdminScreen extends StatefulWidget {
  const UsuariosAdminScreen({super.key});

  @override
  State<UsuariosAdminScreen> createState() => _UsuariosAdminScreenState();
}

class _UsuariosAdminScreenState extends State<UsuariosAdminScreen> {
  static const _roles = [(null, 'Todos'), ('cliente', 'Clientes'), ('vendedor', 'Vendedores'), ('repartidor', 'Repartidores'), ('administrador', 'Admins')];

  static const _estados = [(null, 'Todos', 'todos'), ('activo', 'Activas', 'activo'), ('sinactividad', 'Inactivas', 'sinactividad'), ('temporal', 'Bloqueo temporal', 'temporal'), ('bloqueado', 'Bloqueadas', 'bloqueado'), ('inactivo', 'Dadas de baja', 'inactivo')];

  String? _rol;
  String? _estado;
  Map<String, int> _conteos = {};
  final _busqueda = TextEditingController();
  Timer? _espera;
  List<UsuarioAdmin> _usuarios = [];
  int _total = 0;
  bool _hayMas = false;
  int _pagina = 1;
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargar();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _cargarMas();
    });
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _espera?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => (_cargando = _usuarios.isEmpty, _error = null, _pagina = 1));
    try {
      final r = await AdminService.usuarios(rol: _rol, estado: _estado, busqueda: _busqueda.text);
      if (mounted) setState(() => (_usuarios = r.pagina.items, _hayMas = r.pagina.hayMas, _total = r.pagina.total, _conteos = r.conteos, _cargando = false));
    } catch (e) {
      if (mounted) setState(() => (_error = textoDeError(e), _cargando = false));
    }
  }

  Future<void> _cargarMas() async {
    if (!_hayMas || _cargandoMas || _cargando) return;
    setState(() => _cargandoMas = true);
    try {
      final r = await AdminService.usuarios(rol: _rol, estado: _estado, busqueda: _busqueda.text, pagina: _pagina + 1);
      if (mounted) setState(() => (_usuarios = [..._usuarios, ...r.pagina.items], _hayMas = r.pagina.hayMas, _pagina = _pagina + 1));
    } catch (_) {
      // se reintenta al volver a llegar al final
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  Future<void> _abrir(UsuarioAdmin u) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => UsuarioAdminScreen(usuario: u.usuario, inicial: u)));
    if (mounted) _cargar();
  }

  Future<void> _crear() async {
    final nuevo = await Navigator.push<UsuarioAdmin>(context, MaterialPageRoute(builder: (_) => const FormularioUsuarioScreen()));
    if (nuevo == null || !mounted) return;
    Confeti.lanzar(context);
    mostrarExito(context, '¡Cuenta de ${nuevo.nombre} creada! Su usuario es @${nuevo.usuario}');
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(
      appBar: AppBar(title: Text(_cargando ? 'Usuarios' : 'Usuarios · $_total'), automaticallyImplyLeading: false),
      botonFlotante: FloatingActionButton.extended(onPressed: _crear, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Nueva cuenta')),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _busqueda,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: (_) {
                setState(() {});
                _espera?.cancel();
                _espera = Timer(const Duration(milliseconds: 400), _cargar);
              },
              decoration: InputDecoration(
                hintText: 'Nombre, usuario, correo o cédula',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _busqueda.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
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
                for (final (valor, texto) in _roles)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: valor == null ? null : Icon(UsuarioAdmin.iconosRol[valor], size: 18),
                      label: Text(texto),
                      selected: _rol == valor,
                      onSelected: (_) {
                        setState(() => (_rol = valor, _usuarios = []));
                        _cargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          // Estado de la cuenta, con cuántas hay en cada uno
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                for (final (valor, texto, clave) in _estados)
                  if (valor == null || (_conteos[clave] ?? 0) > 0 || _estado == valor)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_conteos[clave] == null ? texto : '$texto · ${_conteos[clave]}'),
                        selected: _estado == valor,
                        onSelected: (_) {
                          setState(() => (_estado = valor, _usuarios = []));
                          _cargar();
                        },
                      ),
                    ),
              ],
            ),
          ),
          Expanded(child: _contenido()),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 6);
    if (_error != null && _usuarios.isEmpty) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar las cuentas', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }
    if (_usuarios.isEmpty) return const EstadoVacio(icono: Icons.person_search_rounded, titulo: 'Nadie por aquí', mensaje: 'No encontramos cuentas con esa búsqueda');
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        itemCount: _usuarios.length + (_hayMas ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == _usuarios.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          final u = _usuarios[i];
          return Aparecer(key: ValueKey('u-${u.usuario}'), indice: i, child: _TarjetaUsuario(u: u, onTap: () => _abrir(u)));
        },
      ),
    );
  }
}

class _TarjetaUsuario extends StatelessWidget {
  const _TarjetaUsuario({required this.u, required this.onTap});

  final UsuarioAdmin u;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final (estado, colorEstado, iconoEstado) = u.estadoVisible;
    return TarjetaValle(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Hero(
            tag: 'avatar-${u.usuario}',
            child: Opacity(opacity: u.activo && !u.bloqueoTemporal ? 1 : 0.5, child: AvatarValle(nombre: u.nombre, apellido: u.apellido, fotoUrl: u.foto, tamano: 50, color: u.colorRol)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Formato.titulo(u.nombreCompleto), style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('@${u.usuario} · ${u.email ?? ''}', style: tema.bodySmall?.copyWith(color: c.textoSuave), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  InsigniaValle(UsuarioAdmin.etiquetasRol[u.rol] ?? u.rol, color: u.colorRol, icono: UsuarioAdmin.iconosRol[u.rol]),
                  InsigniaValle(estado, color: colorEstado, icono: iconoEstado),
                ]),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textoSuave),
        ],
      ),
    );
  }
}

// =============================================================================================
// Una cuenta: ver y hacer de todo con ella
// =============================================================================================
class UsuarioAdminScreen extends StatefulWidget {
  const UsuarioAdminScreen({super.key, required this.usuario, this.inicial});

  final String usuario;
  final UsuarioAdmin? inicial;

  @override
  State<UsuarioAdminScreen> createState() => _UsuarioAdminScreenState();
}

class _UsuarioAdminScreenState extends State<UsuarioAdminScreen> {
  late UsuarioAdmin? _u = widget.inicial;
  String? _error;
  bool _ocupado = false;
  bool _subiendoFoto = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final u = await AdminService.usuario(widget.usuario);
      if (mounted) setState(() => (_u = u, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _hacer(Future<UsuarioAdmin> Function() accion, String exito) async {
    setState(() => _ocupado = true);
    try {
      final u = await accion();
      if (!mounted) return;
      setState(() => _u = u);
      HapticFeedback.mediumImpact();
      mostrarExito(context, exito);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _foto() async {
    final base64 = await elegirImagenBase64(context, titulo: 'Foto de ${_u!.nombre}');
    if (base64 == null || !mounted) return;
    setState(() => _subiendoFoto = true);
    await _hacer(() => AdminService.fotoUsuario(widget.usuario, base64), 'Foto actualizada');
    if (mounted) setState(() => _subiendoFoto = false);
  }

  Future<void> _editar() async {
    final u = await Navigator.push<UsuarioAdmin>(context, MaterialPageRoute(builder: (_) => FormularioUsuarioScreen(editar: _u)));
    if (u != null && mounted) {
      setState(() => _u = u);
      mostrarExito(context, 'Datos guardados');
    }
  }

  Future<void> _clave() async {
    final clave = await mostrarHoja<String>(context, isScrollControlled: true, showDragHandle: true, builder: (_) => _HojaClave(nombre: _u!.nombre));
    if (clave != null) await _hacer(() => AdminService.ponerClave(widget.usuario, clave), 'Contraseña cambiada. Se cerraron sus sesiones');
  }

  Future<void> _bloquear() async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Bloquear a ${_u!.nombre}',
      explicacion: 'No podrá entrar hasta que la desbloquees. Se cierran todas sus sesiones al instante.',
      textoBoton: 'Bloquear cuenta',
      sugerencias: const ['Pedidos falsos', 'Lenguaje ofensivo', 'Intento de fraude', 'Lo pidió el usuario'],
      minimo: 3,
    );
    if (motivo != null) await _hacer(() => AdminService.cambiarEstadoUsuario(widget.usuario, activo: false, motivo: motivo), 'Cuenta bloqueada');
  }

  Future<void> _darDeBaja() async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Dar de baja a ${_u!.nombre}',
      explicacion: 'La cuenta queda inactiva: no se borra su historial (pedidos, calificaciones) y la puedes reactivar cuando quieras.',
      textoBoton: 'Dar de baja',
      sugerencias: const ['Lo pidió el usuario', 'Cuenta duplicada', 'Ya no trabaja con nosotros'],
      minimo: 3,
    );
    if (motivo != null) await _hacer(() => AdminService.darDeBaja(widget.usuario, motivo), 'Cuenta dada de baja');
  }

  Future<void> _reactivar() => _hacer(() => AdminService.cambiarEstadoUsuario(widget.usuario, activo: true), _u?.estatus == 'bloqueado' ? '¡Cuenta desbloqueada!' : '¡Cuenta reactivada!');
  Future<void> _quitarBloqueoTemporal() => _hacer(() => AdminService.quitarBloqueoTemporal(widget.usuario), 'Listo: ya puede entrar');

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return FondoValle(
      titulo: 'Cuenta',
      child: u == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar la cuenta', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 3, conImagen: false))
          : RefreshIndicator(onRefresh: _cargar, child: _contenido(u)),
    );
  }

  Widget _contenido(UsuarioAdmin u) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final (estado, colorEstado, iconoEstado) = u.estadoVisible;
    final protegido = u.usuario == 'admin';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Cabecera con la foto (tocarla la cambia)
        TarjetaValle(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              GestureDetector(
                onTap: _ocupado ? null : _foto,
                child: Stack(
                  children: [
                    Hero(tag: 'avatar-${u.usuario}', child: AvatarValle(nombre: u.nombre, apellido: u.apellido, fotoUrl: u.foto, tamano: 104, color: u.colorRol)),
                    if (_subiendoFoto)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: c.primario, shape: BoxShape.circle, border: Border.all(color: c.tarjeta, width: 3)),
                        child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(Formato.titulo(u.nombreCompleto), style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              Text('@${u.usuario}', style: tema.bodyMedium?.copyWith(color: c.textoSuave)),
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                InsigniaValle(UsuarioAdmin.etiquetasRol[u.rol] ?? u.rol, color: u.colorRol, icono: UsuarioAdmin.iconosRol[u.rol]),
                InsigniaValle(estado, color: colorEstado, icono: iconoEstado),
              ]),
            ],
          ),
        ),

        const EncabezadoSeccion('Datos'),
        TarjetaValle(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _Dato(Icons.alternate_email_rounded, 'Correo', u.email ?? '—'),
              _Dato(Icons.badge_outlined, 'Cédula', u.cedula ?? '—'),
              _Dato(Icons.phone_iphone_rounded, 'Teléfono', u.telefono == null ? '—' : Formato.telefono(u.telefono!),
                  accion: u.telefono == null ? null : IconButton(icon: const Icon(Icons.call_rounded), color: c.primario, onPressed: () => llamar(context, u.telefono!))),
              _Dato(Icons.event_rounded, 'Se unió', u.creadoEn == null ? '—' : Formato.fechaRelativa(u.creadoEn!)),
              _Dato(Icons.access_time_rounded, 'Última conexión', u.ultimaConexion == null ? 'Nunca' : Formato.hace(u.ultimaConexion!)),
            ],
          ),
        ),

        const EncabezadoSeccion('Acciones'),
        TarjetaValle(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _Accion(Icons.edit_rounded, 'Editar datos', 'Nombre, correo, cédula y teléfono', onTap: _ocupado ? null : _editar),
              _Accion(Icons.add_a_photo_rounded, 'Cambiar foto', 'Desde la cámara o la galería', onTap: _ocupado ? null : _foto),
              _Accion(Icons.password_rounded, 'Poner contraseña nueva', 'Si la olvidó; se cierran sus sesiones', onTap: _ocupado ? null : _clave),
            ],
          ),
        ),
        const EncabezadoSeccion('Estado de la cuenta'),
        // Qué le pasa a la cuenta, con la acción que corresponde
        if (u.eliminada || u.estatus != 'activo' || u.bloqueoTemporal || u.intentosFallidos > 0 || u.sinActividadDias != null) ...[
          TarjetaValle(
            color: colorEstado.withValues(alpha: 0.10),
            colorBorde: colorEstado.withValues(alpha: 0.5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(iconoEstado, color: colorEstado),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  u.eliminada
                      ? 'La persona eliminó esta cuenta: sus datos personales ya se borraron y no se puede reactivar.'
                      : switch (u.estatus) {
                          'bloqueado' => 'Esta cuenta está bloqueada: no puede entrar a la app hasta que la desbloquees.',
                          'inactivo' => 'Esta cuenta está dada de baja: no puede entrar, pero su historial se conserva.',
                          _ when u.bloqueoTemporal =>
                            'Se bloqueó sola por escribir mal la contraseña ${u.intentosFallidos > 0 ? '${u.intentosFallidos} veces' : '5 veces'}. Podrá entrar a las ${Formato.hora(u.bloqueadoHasta!)}, o desbloquéala ahora.',
                          _ when u.intentosFallidos > 0 => 'Lleva ${u.intentosFallidos} ${u.intentosFallidos == 1 ? 'intento fallido' : 'intentos fallidos'} de contraseña. A los 5 se bloquea 15 minutos.',
                          _ => 'No abre la app hace ${u.sinActividadDias} días. Puede entrar normalmente: vuelve a estar activa apenas lo haga.',
                        },
                  style: tema.bodyMedium,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        if (!u.eliminada)
          TarjetaValle(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                if (u.bloqueoTemporal || (u.estatus == 'activo' && u.intentosFallidos > 0))
                  _Accion(Icons.lock_open_rounded, u.bloqueoTemporal ? 'Desbloquear ahora' : 'Reiniciar intentos', 'Sin cambiar su contraseña', color: AppTheme.successColor, onTap: _ocupado ? null : _quitarBloqueoTemporal),
                if (!protegido && u.estatus == 'bloqueado') _Accion(Icons.lock_open_rounded, 'Desbloquear cuenta', 'Vuelve a poder entrar', color: AppTheme.successColor, onTap: _ocupado ? null : _reactivar),
                if (!protegido && u.estatus == 'inactivo') _Accion(Icons.check_circle_rounded, 'Reactivar cuenta', 'Vuelve a poder entrar', color: AppTheme.successColor, onTap: _ocupado ? null : _reactivar),
                if (!protegido && u.estatus == 'activo') _Accion(Icons.block_rounded, 'Bloquear', 'No podrá entrar hasta que la desbloquees', color: AppTheme.errorColor, onTap: _ocupado ? null : _bloquear),
                if (!protegido && u.estatus != 'inactivo') _Accion(Icons.person_off_rounded, 'Dar de baja', 'Queda inactiva sin borrar su historial', color: AppTheme.warningColor, onTap: _ocupado ? null : _darDeBaja),
                if (protegido && !u.bloqueoTemporal && u.intentosFallidos == 0)
                  const ListTile(leading: Icon(Icons.shield_rounded), title: Text('Cuenta principal'), subtitle: Text('No se puede bloquear ni dar de baja')),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.titulo, this.valor, {this.accion});

  final IconData icono;
  final String titulo;
  final String valor;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return ListTile(
      leading: Icon(icono, color: c.primario),
      title: Text(titulo, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.textoSuave)),
      subtitle: Text(valor, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      trailing: accion,
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion(this.icono, this.titulo, this.detalle, {this.onTap, this.color});

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tinte = color ?? c.primario;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: tinte.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
        child: Icon(icono, color: tinte, size: 20),
      ),
      title: Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      subtitle: Text(detalle),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textoSuave),
    );
  }
}

class _HojaClave extends StatefulWidget {
  const _HojaClave({required this.nombre});

  final String nombre;

  @override
  State<_HojaClave> createState() => _HojaClaveState();
}

class _HojaClaveState extends State<_HojaClave> {
  final _clave = TextEditingController();

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valida = _clave.text.length >= 6;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Contraseña nueva para ${widget.nombre}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Se la enviaremos a su correo y se cerrarán sus sesiones abiertas.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            CampoValle(controller: _clave, etiqueta: 'Contraseña nueva', icono: Icons.lock_outline_rounded, esClave: true, accion: TextInputAction.done, onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            MedidorClave(clave: _clave.text),
            const SizedBox(height: 16),
            BotonValle(texto: 'Guardar contraseña', icono: Icons.check_rounded, onPressed: valida ? () => Navigator.pop(context, _clave.text) : null),
          ],
        ),
      ),
    );
  }
}

// =============================================================================================
// Crear o editar una cuenta
// =============================================================================================
class FormularioUsuarioScreen extends StatefulWidget {
  const FormularioUsuarioScreen({super.key, this.editar});

  /// Si viene, se editan sus datos; si no, se crea una cuenta nueva
  final UsuarioAdmin? editar;

  @override
  State<FormularioUsuarioScreen> createState() => _FormularioUsuarioScreenState();
}

class _FormularioUsuarioScreenState extends State<FormularioUsuarioScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.editar?.nombre ?? '');
  late final _apellido = TextEditingController(text: widget.editar?.apellido ?? '');
  late final _email = TextEditingController(text: widget.editar?.email ?? '');
  late final _cedula = TextEditingController(text: widget.editar?.cedula ?? '');
  late final _telefono = TextEditingController(text: widget.editar?.telefono ?? '');
  final _clave = TextEditingController();
  final _negocio = TextEditingController();
  final _placa = TextEditingController();
  final _color = TextEditingController();
  String _rol = 'cliente';
  String? _categoria = '001';
  Vehiculo _vehiculo = Vehiculo.moto;
  bool _enviarCorreo = true;
  List<Categoria> _categorias = [];
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.editar != null;

  @override
  void initState() {
    super.initState();
    if (!_editando) CatalogoService.categorias().then((c) => mounted ? setState(() => _categorias = c) : null).catchError((_) => null);
  }

  @override
  void dispose() {
    for (final c in [_nombre, _apellido, _email, _cedula, _telefono, _clave, _negocio, _placa, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => (_guardando = true, _error = null));
    try {
      final datos = {
        'nombre': _nombre.text.trim(),
        'apellido': _apellido.text.trim(),
        'email': _email.text.trim(),
        'cedula': _cedula.text.trim(),
        'telefono': _telefono.text.trim(),
      };
      final UsuarioAdmin u;
      if (_editando) {
        final e = widget.editar!;
        final cambios = {
          for (final MapEntry(:key, :value) in datos.entries)
            if (value != (switch (key) { 'nombre' => e.nombre, 'apellido' => e.apellido, 'email' => e.email, 'cedula' => e.cedula, _ => e.telefono } ?? '')) key: value,
        };
        u = cambios.isEmpty ? e : await AdminService.editarUsuario(e.usuario, cambios);
      } else {
        u = await AdminService.crearUsuario({
          ...datos,
          'password': _clave.text,
          'rol': _rol,
          'enviarCorreo': _enviarCorreo,
          if (_rol == 'vendedor') ...{'nombreNegocio': _negocio.text.trim(), 'categoriaNegocio': _categoria},
          if (_rol == 'repartidor') ...{'vehiculo': _vehiculo.codigo, if (_vehiculo.llevaPlaca) 'placa': _placa.text.trim(), 'color': _color.text.trim()},
        });
      }
      if (mounted) Navigator.pop(context, u);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _requerido(String? v, String que) => (v ?? '').trim().isEmpty ? 'Escribe $que' : null;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return FondoValle(
      titulo: _editando ? 'Editar cuenta' : 'Nueva cuenta',
      barraInferior: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
          child: BotonValle(texto: _editando ? 'Guardar cambios' : 'Crear cuenta', icono: _editando ? Icons.check_rounded : Icons.person_add_alt_1_rounded, cargando: _guardando, onPressed: _guardar),
        ),
      ),
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!_editando) ...[
              const EncabezadoSeccion('¿Qué tipo de cuenta?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rol in const ['cliente', 'vendedor', 'repartidor', 'administrador'])
                    ChoiceChip(
                      avatar: Icon(UsuarioAdmin.iconosRol[rol], size: 18, color: _rol == rol ? Colors.white : UsuarioAdmin.coloresRol[rol]),
                      label: Text(UsuarioAdmin.etiquetasRol[rol]!),
                      selected: _rol == rol,
                      onSelected: (_) => setState(() => _rol = rol),
                    ),
                ],
              ),
              if (_rol == 'administrador')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: InsigniaValle('Tendrá acceso total al panel', color: AppTheme.warningColor, icono: Icons.warning_amber_rounded),
                ),
            ],
            const EncabezadoSeccion('Datos personales'),
            CampoValle(controller: _nombre, etiqueta: 'Nombres', icono: Icons.person_outline_rounded, mayusculas: TextCapitalization.words, maxLongitud: 100, validator: (v) => _requerido(v, 'el nombre')),
            const SizedBox(height: 12),
            CampoValle(controller: _apellido, etiqueta: 'Apellidos', icono: Icons.person_outline_rounded, mayusculas: TextCapitalization.words, maxLongitud: 100, validator: (v) => _requerido(v, 'el apellido')),
            const SizedBox(height: 12),
            CampoValle(controller: _cedula, etiqueta: 'Cédula', icono: Icons.badge_outlined, tipoTeclado: TextInputType.number, maxLongitud: 10, formateadores: [FilteringTextInputFormatter.digitsOnly], validator: (v) => Validadores.cedula(v ?? '') ? null : 'Cédula inválida'),
            const SizedBox(height: 12),
            CampoValle(controller: _email, etiqueta: 'Correo', icono: Icons.alternate_email_rounded, tipoTeclado: TextInputType.emailAddress, validator: (v) => Validadores.email(v ?? '') ? null : 'Correo inválido'),
            const SizedBox(height: 12),
            CampoValle(controller: _telefono, etiqueta: 'Teléfono', icono: Icons.phone_iphone_rounded, tipoTeclado: TextInputType.phone, maxLongitud: 10, formateadores: [FilteringTextInputFormatter.digitsOnly], validator: (v) => Validadores.telefono(v ?? '') ? null : 'Debe empezar con 09 y tener 10 dígitos'),
            if (!_editando) ...[
              const SizedBox(height: 12),
              CampoValle(controller: _clave, etiqueta: 'Contraseña inicial', icono: Icons.lock_outline_rounded, esClave: true, validator: (v) => (v ?? '').length >= 6 ? null : 'Mínimo 6 caracteres', ayuda: 'Dísela al usuario; podrá cambiarla en su perfil'),
            ],
            if (!_editando && _rol == 'vendedor') ...[
              const EncabezadoSeccion('Su negocio', subtitulo: 'Nace aprobado; el resto lo completa en "Mi negocio"'),
              CampoValle(controller: _negocio, etiqueta: 'Nombre del negocio', icono: Icons.storefront_rounded, mayusculas: TextCapitalization.words, maxLongitud: 120, validator: (v) => _requerido(v, 'el nombre del negocio')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoria,
                decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.category_rounded)),
                items: [for (final cat in _categorias) DropdownMenuItem(value: cat.codigo, child: Text(cat.descripcion))],
                onChanged: (v) => setState(() => _categoria = v),
              ),
            ],
            if (!_editando && _rol == 'repartidor') ...[
              const EncabezadoSeccion('Su vehículo', subtitulo: 'Nace aprobado y listo para repartir'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in Vehiculo.values)
                    ChoiceChip(avatar: Icon(v.icono, size: 18), label: Text(v.etiqueta), selected: _vehiculo == v, onSelected: (_) => setState(() => _vehiculo = v)),
                ],
              ),
              if (_vehiculo.llevaPlaca) ...[
                const SizedBox(height: 12),
                CampoValle(controller: _placa, etiqueta: 'Placa', icono: Icons.pin_rounded, mayusculas: TextCapitalization.characters, maxLongitud: 8, validator: (v) => Validadores.placa(v ?? '') ? null : 'Placa inválida (ej: ABC-1234)'),
              ],
              const SizedBox(height: 12),
              CampoValle(controller: _color, etiqueta: 'Color (opcional)', icono: Icons.palette_outlined, mayusculas: TextCapitalization.sentences, maxLongitud: 30),
            ],
            if (!_editando) ...[
              const SizedBox(height: 16),
              TarjetaValle(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SwitchListTile(
                  value: _enviarCorreo,
                  onChanged: (v) => setState(() => _enviarCorreo = v),
                  secondary: const Icon(Icons.mark_email_read_rounded),
                  title: const Text('Enviarle sus datos por correo'),
                  subtitle: const Text('Le llega un correo de bienvenida con su usuario y la contraseña temporal'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              TarjetaValle(
                color: AppTheme.errorColor.withValues(alpha: 0.12),
                colorBorde: AppTheme.errorColor.withValues(alpha: 0.5),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: AppTheme.errorColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: tema.bodyMedium)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
