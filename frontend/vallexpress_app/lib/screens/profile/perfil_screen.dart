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
import '../../widgets/ui/ui.dart';
import 'addresses_screen.dart';
import 'settings_screen.dart';
import 'telefonos_screen.dart';

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
        TelefonoService.listar().then<Object?>((v) => v).catchError((_) => <Telefono>[]),
        AddressService.listar().then<Object?>((v) => v).catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _usuario = resultados[0] as Map<String, dynamic>;
        _telefonos = resultados[1] as List<Telefono>;
        _direcciones = (resultados[2] as List<dynamic>).map((d) => Direccion.desdeJson(d as Map<String, dynamic>)).toList();
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
      builder: (_) => _FormularioNombre(nombre: '${u['nombre'] ?? ''}', apellido: '${u['apellido'] ?? ''}'),
    );
    if (cambios == null || !mounted) return;
    await context.read<AuthProvider>().actualizarUsuario(cambios); // el saludo del inicio cambia al instante
    if (!mounted) return;
    mostrarExito(context, 'Datos actualizados');
    await _cargar();
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
        content: const Text('Tendrás que escribir tu contraseña la próxima vez que quieras entrar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(titulo: 'Mi perfil', child: _contenido());
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null || _usuario == null) {
      return EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar tu perfil', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar);
    }

    final u = _usuario!;
    final c = context.colores;
    final rol = '${u['tipoUsuario'] ?? 'cliente'}';
    final (colorRol, etiquetaRol) = switch (rol) {
      'vendedor' => (AppTheme.vendedorColor, 'Vendedor'),
      'repartidor' => (AppTheme.repartidorColor, 'Repartidor'),
      'administrador' => (AppTheme.infoColor, 'Administrador'),
      _ => (AppTheme.clienteColor, 'Cliente'),
    };
    final predeterminada = _direcciones.where((d) => d.esPredeterminada).firstOrNull ?? _direcciones.firstOrNull;
    final principal = _telefonos.where((t) => t.principal).firstOrNull ?? _telefonos.firstOrNull;
    final nombreCompleto = Formato.titulo('${u['nombre'] ?? ''} ${u['apellido'] ?? ''}');

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ------------------------------ Cabecera ------------------------------
          TarjetaValle(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                AvatarValle(nombre: '${u['nombre'] ?? ''}', apellido: '${u['apellido'] ?? ''}', tamano: 76, color: colorRol),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombreCompleto, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('@${u['usuario'] ?? u['id'] ?? ''}', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          InsigniaValle(etiquetaRol, color: colorRol),
                          if (u['verificado'] == true) const InsigniaValle('Correo verificado', color: AppTheme.successColor, icono: Icons.verified_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------ Mis datos ------------------------------
          const SizedBox(height: 12),
          const EncabezadoSeccion('Mis datos'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Fila(icono: Icons.person_outline, titulo: 'Nombre', valor: nombreCompleto, trailing: const Icon(Icons.edit_outlined, size: 20), onTap: _editarNombre),
                const _Separador(),
                _Fila(icono: Icons.badge_outlined, titulo: 'Cédula', valor: '${u['cedula'] ?? '—'}', trailing: Icon(Icons.lock_outline, size: 18, color: c.textoSuave)),
                const _Separador(),
                _Fila(icono: Icons.alternate_email, titulo: 'Correo', valor: '${u['email'] ?? '—'}', trailing: Icon(Icons.lock_outline, size: 18, color: c.textoSuave)),
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
                  valor: principal == null ? 'Agrega tu primer teléfono' : '${Formato.telefono(principal.numero)}${_telefonos.length > 1 ? '  ·  +${_telefonos.length - 1}' : ''}',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _abrir(const TelefonosScreen()),
                ),
                const _Separador(),
                _Fila(
                  icono: Icons.location_on_outlined,
                  titulo: 'Mis direcciones',
                  valor: predeterminada == null ? 'Agrega tu primera dirección' : '${predeterminada.titulo}: ${predeterminada.direccion}',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _abrir(const AddressesScreen()),
                ),
              ],
            ),
          ),

          // ------------------------------ Cuenta ------------------------------
          const SizedBox(height: 12),
          const EncabezadoSeccion('Cuenta'),
          TarjetaValle(
            padding: EdgeInsets.zero,
            child: _Fila(
              icono: Icons.settings_outlined,
              titulo: 'Configuración',
              valor: 'Apariencia, contraseña, notificaciones y más',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _abrir(const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          BotonValle(texto: 'Cerrar sesión', icono: Icons.logout_rounded, tipo: TipoBoton.secundario, onPressed: _cerrarSesion),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.icono, required this.titulo, required this.valor, this.trailing, this.onTap});

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
              decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icono, size: 20, color: c.primario),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: tema.labelMedium?.copyWith(color: c.textoSuave)),
                  const SizedBox(height: 2),
                  Text(valor, style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) IconTheme(data: IconThemeData(color: c.textoSuave), child: trailing!),
          ],
        ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador();

  @override
  Widget build(BuildContext context) => Divider(height: 1, indent: 70, color: context.colores.borde);
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
  late final TextEditingController _nombre = TextEditingController(text: widget.nombre);
  late final TextEditingController _apellido = TextEditingController(text: widget.apellido);
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
      if (mounted) Navigator.pop(context, {'nombre': nombre, 'apellido': apellido});
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Editar mis datos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            CampoValle(controller: _nombre, etiqueta: 'Nombres', icono: Icons.person_outline, mayusculas: TextCapitalization.words, maxLongitud: 100),
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
              ayuda: _error ?? 'Tu cédula y tu correo no se pueden cambiar desde aquí',
            ),
            const SizedBox(height: 20),
            BotonValle(texto: 'Guardar cambios', icono: Icons.check_rounded, cargando: _guardando, onPressed: _guardar),
          ],
        ),
      ),
    );
  }
}
