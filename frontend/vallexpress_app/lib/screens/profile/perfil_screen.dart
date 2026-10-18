import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/direccion.dart';
import '../../models/telefono.dart';
import '../../providers/auth_provider.dart';
import '../../services/address_service.dart';
import '../../services/api_error.dart';
import '../../services/profile_service.dart';
import '../../services/telefono_service.dart';
import '../../utils/formato.dart';
import '../../utils/imagen.dart';
import '../../widgets/ui/ui.dart';
import 'addresses_screen.dart';
import 'permisos_screen.dart';
import 'settings_screen.dart';
import 'telefonos_screen.dart';
import '../../services/pedidos_service.dart';
import '../repartidor/vehiculo_screen.dart';
import '../../widgets/documentos_repartidor.dart';
import '../vendedor/mi_negocio_screen.dart';

/// Mi perfil: el mismo para cliente, vendedor y repartidor. Datos de la cuenta, teléfonos, direcciones, configuración
/// y cierre de sesión. (Lo propio de cada rol —negocio, vehículo— se agrega en sus módulos.)
class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _usuario;
  List<Telefono> _telefonos = [];
  List<Direccion> _direcciones = [];
  bool _subiendoFoto = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _usuario == null;
      _error = null;
    });
    try {
      // El perfil es obligatorio; teléfonos y direcciones son un resumen: si fallan, el perfil igual se muestra
      final resultados = await Future.wait<Object?>([
        ProfileService.obtenerPerfil(),
        TelefonoService.listar()
            .then<Object?>((v) => v)
            .catchError((_) => <Telefono>[]),
        AddressService.listar()
            .then<Object?>((v) => v)
            .catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _usuario = resultados[0] as Map<String, dynamic>;
        _telefonos = resultados[1] as List<Telefono>;
        _direcciones = (resultados[2] as List<dynamic>)
            .map((d) => Direccion.desdeJson(d as Map<String, dynamic>))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  Future<void> _editarNombre() async {
    final u = _usuario!;
    final cambios = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormularioNombre(
        nombre: '${u['nombre'] ?? ''}',
        apellido: '${u['apellido'] ?? ''}',
      ),
    );
    if (cambios == null || !mounted) return;
    await context.read<AuthProvider>().actualizarUsuario(
      cambios,
    ); // el saludo del inicio cambia al instante
    if (!mounted) return;
    mostrarExito(context, 'Datos actualizados');
    await _cargar();
  }

  Future<void> _cambiarFoto() async {
    final base64 = await elegirImagenBase64(
      context,
      titulo: 'Tu foto de perfil',
    );
    if (base64 == null || !mounted) return;
    setState(() => _subiendoFoto = true);
    try {
      final url = await ProfileService.subirFoto(base64);
      if (!mounted) return;
      setState(() => _usuario = {...?_usuario, 'fotoPerfil': url});
      await context.read<AuthProvider>().actualizarUsuario({
        'fotoPerfil': url,
      }); // el inicio la muestra al instante
      if (mounted) mostrarExito(context, '¡Foto actualizada! Te ves genial');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    if (mounted) _cargar(); // al volver, el resumen refleja lo que se cambió
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Tendrás que escribir tu contraseña la próxima vez que quieras entrar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(titulo: 'Mi perfil', child: _contenido());
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 4, conImagen: false);
    if (_error != null || _usuario == null) {
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        color: AppTheme.errorColor,
        titulo: 'No pudimos cargar tu perfil',
        mensaje: _error,
        textoAccion: 'Reintentar',
        onAccion: _cargar,
      );
    }

    final u = _usuario!;
    final c = context.colores;
    final rol = '${u['tipoUsuario'] ?? 'cliente'}';
    final (colorRol, etiquetaRol, iconoRol) = switch (rol) {
      'vendedor' => (
        AppTheme.vendedorColor,
        'Vendedor',
        Icons.storefront_rounded,
      ),
      'repartidor' => (
        AppTheme.repartidorColor,
        'Repartidor',
        Icons.two_wheeler_rounded,
      ),
      'administrador' => (
        AppTheme.infoColor,
        'Administrador',
        Icons.admin_panel_settings_rounded,
      ),
      _ => (AppTheme.clienteColor, 'Cliente', Icons.favorite_rounded),
    };
    final predeterminada =
        _direcciones.where((d) => d.esPredeterminada).firstOrNull ??
        _direcciones.firstOrNull;
    final principal =
        _telefonos.where((t) => t.principal).firstOrNull ??
        _telefonos.firstOrNull;
    final nombreCompleto = Formato.titulo(
      '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}',
    );

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ------------------------------ Cabecera ------------------------------
          Aparecer(
            child: _CabeceraPerfil(
              nombre: nombreCompleto,
              usuario: '${u['usuario'] ?? u['id'] ?? ''}',
              iniciales: ('${u['nombre'] ?? ''}', '${u['apellido'] ?? ''}'),
              foto: u['fotoPerfil']?.toString(),
              color: colorRol,
              etiquetaRol: etiquetaRol,
              iconoRol: iconoRol,
              verificado: u['verificado'] == true,
              subiendo: _subiendoFoto,
              onFoto: _cambiarFoto,
            ),
          ),

          // ------------------------------ Mis datos ------------------------------
          const SizedBox(height: 12),
          const EncabezadoSeccion('Mis datos'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Fila(
                  icono: Icons.person_outline,
                  titulo: 'Nombre',
                  valor: nombreCompleto,
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: _editarNombre,
                ),
                const _Separador(),
                _Fila(
                  icono: Icons.badge_outlined,
                  titulo: 'Cédula',
                  valor: '${u['cedula'] ?? '—'}',
                  trailing: Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: c.textoSuave,
                  ),
                ),
                const _Separador(),
                _Fila(
                  icono: Icons.alternate_email,
                  titulo: 'Correo',
                  valor: '${u['email'] ?? '—'}',
                  trailing: Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: c.textoSuave,
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------ Contacto y entrega ------------------------------
          const SizedBox(height: 12),
          const EncabezadoSeccion('Contacto y entrega'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Fila(
                  icono: Icons.phone_iphone_outlined,
                  titulo: 'Mis teléfonos',
                  valor: principal == null
                      ? 'Agrega tu primer teléfono'
                      : '${Formato.telefono(principal.numero)}${_telefonos.length > 1 ? '  ·  +${_telefonos.length - 1}' : ''}',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _abrir(const TelefonosScreen()),
                ),
                const _Separador(),
                _Fila(
                  icono: Icons.location_on_outlined,
                  titulo: 'Mis direcciones',
                  valor: predeterminada == null
                      ? 'Agrega tu primera dirección'
                      : '${predeterminada.titulo}: ${predeterminada.direccion}',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _abrir(const AddressesScreen()),
                ),
              ],
            ),
          ),

          if (rol == 'repartidor') ...[
            const SizedBox(height: 12),
            const EncabezadoSeccion('Reparto'),
            TarjetaValle(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _Fila(
                    icono: Icons.two_wheeler_rounded,
                    titulo: 'Mi vehículo',
                    valor: 'Tipo, placa y color',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final perfil = await PedidosService.miPerfilRepartidor()
                          .catchError((_) => null);
                      if (mounted) _abrir(VehiculoScreen(actual: perfil));
                    },
                  ),
                  Divider(height: 1, color: context.colores.borde),
                  _Fila(
                    icono: Icons.verified_user_rounded,
                    titulo: 'Mis documentos',
                    valor: 'Cédula, selfie, licencia y matrícula',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _abrir(const MisDocumentosScreen()),
                  ),
                ],
              ),
            ),
          ],

          if (rol == 'vendedor') ...[
            const SizedBox(height: 12),
            const EncabezadoSeccion('Mi negocio'),
            TarjetaValle(
              padding: EdgeInsets.zero,
              child: _Fila(
                icono: Icons.storefront_rounded,
                titulo: 'Mi negocio',
                valor: 'Datos, horario, ubicación y productos',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _abrir(const MiNegocioScreen()),
              ),
            ),
          ],

          // ------------------------------ Cuenta ------------------------------
          const SizedBox(height: 12),
          const EncabezadoSeccion('Cuenta'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (!kIsWeb && rol != 'administrador') ...[
                  _Fila(
                    icono: Icons.phonelink_setup_rounded,
                    titulo: 'Permisos del celular',
                    valor: rol == 'repartidor' ? 'Ubicación, notificaciones y batería' : 'Notificaciones',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _abrir(PermisosScreen(rol: rol)),
                  ),
                  const _Separador(),
                ],
                _Fila(
                  icono: Icons.settings_outlined,
                  titulo: 'Configuración',
                  valor: 'Apariencia, contraseña, notificaciones y más',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _abrir(const SettingsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          BotonValle(
            texto: 'Cerrar sesión',
            icono: Icons.logout_rounded,
            tipo: TipoBoton.secundario,
            onPressed: _cerrarSesion,
          ),
        ],
      ),
    );
  }
}

/// Cabecera del perfil: banner con el degradado del rol, la foto (o las iniciales) con un botón de cámara,
/// el nombre, el usuario y las insignias. Tocar la foto la cambia.
class _CabeceraPerfil extends StatelessWidget {
  const _CabeceraPerfil({
    required this.nombre,
    required this.usuario,
    required this.iniciales,
    required this.foto,
    required this.color,
    required this.etiquetaRol,
    required this.iconoRol,
    required this.verificado,
    required this.subiendo,
    required this.onFoto,
  });

  final String nombre;
  final String usuario;
  final (String, String) iniciales;
  final String? foto;
  final Color color;
  final String etiquetaRol;
  final IconData iconoRol;
  final bool verificado;
  final bool subiendo;
  final VoidCallback onFoto;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return TarjetaValle(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Banner con el color del rol y burbujas decorativas; la foto se monta sobre su borde
          SizedBox(
            height: 190,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 130,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  color,
                                  Color.lerp(
                                    color,
                                    AppTheme.accentColor,
                                    0.45,
                                  )!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -30,
                          top: -40,
                          child: _Burbuja(
                            tamano: 150,
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        Positioned(
                          left: 30,
                          bottom: -60,
                          child: _Burbuja(
                            tamano: 120,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          top: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(iconoRol, size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  etiquetaRol,
                                  style: tema.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: Pulsable(
                      onTap: subiendo ? null : onFoto,
                      child: GestureDetector(
                        onTap: subiendo ? null : onFoto,
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: c.tarjeta,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                child: AvatarValle(
                                  key: ValueKey(foto),
                                  nombre: iniciales.$1,
                                  apellido: iniciales.$2,
                                  fotoUrl: foto,
                                  tamano: 104,
                                  color: color,
                                ),
                              ),
                            ),
                            if (subiendo)
                              Positioned.fill(
                                child: Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: c.primario,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: c.tarjeta,
                                    width: 3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.photo_camera_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Text(
                  nombre,
                  style: tema.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '@$usuario',
                  style: tema.bodyMedium?.copyWith(color: c.textoSuave),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InsigniaValle(etiquetaRol, color: color, icono: iconoRol),
                    if (verificado)
                      const InsigniaValle(
                        'Correo verificado',
                        color: AppTheme.successColor,
                        icono: Icons.verified_rounded,
                      ),
                    if (foto == null)
                      InsigniaValle(
                        'Toca la foto para agregar una',
                        color: c.textoSuave,
                        icono: Icons.add_a_photo_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.tamano, required this.color});

  final double tamano;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: tamano,
    height: tamano,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.trailing,
    this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.primario.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, size: 20, color: c.primario),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: tema.labelMedium?.copyWith(color: c.textoSuave),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: tema.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null)
              IconTheme(
                data: IconThemeData(color: c.textoSuave),
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 70, color: context.colores.borde);
}

/// Hoja inferior para editar nombre y apellido
class _FormularioNombre extends StatefulWidget {
  const _FormularioNombre({required this.nombre, required this.apellido});

  final String nombre;
  final String apellido;

  @override
  State<_FormularioNombre> createState() => _FormularioNombreState();
}

class _FormularioNombreState extends State<_FormularioNombre> {
  late final TextEditingController _nombre = TextEditingController(
    text: widget.nombre,
  );
  late final TextEditingController _apellido = TextEditingController(
    text: widget.apellido,
  );
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    final nombre = _nombre.text.trim();
    final apellido = _apellido.text.trim();
    if (nombre.length < 2) return setState(() => _error = 'Escribe tu nombre');
    if (apellido.isEmpty) return setState(() => _error = 'Escribe tu apellido');

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ProfileService.actualizarPerfil(nombre: nombre, apellido: apellido);
      if (mounted) {
        Navigator.pop(context, {'nombre': nombre, 'apellido': apellido});
      }
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar mis datos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            CampoValle(
              controller: _nombre,
              etiqueta: 'Nombres',
              icono: Icons.person_outline,
              mayusculas: TextCapitalization.words,
              maxLongitud: 100,
            ),
            const SizedBox(height: 14),
            CampoValle(
              controller: _apellido,
              etiqueta: 'Apellidos',
              icono: Icons.person_outline,
              mayusculas: TextCapitalization.words,
              maxLongitud: 100,
              accion: TextInputAction.done,
              onSubmitted: (_) => _guardando ? null : _guardar(),
              estado: _error == null ? EstadoCampo.neutro : EstadoCampo.error,
              ayuda:
                  _error ??
                  'Tu cédula y tu correo no se pueden cambiar desde aquí',
            ),
            const SizedBox(height: 20),
            BotonValle(
              texto: 'Guardar cambios',
              icono: Icons.check_rounded,
              cargando: _guardando,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
