import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_error.dart';
import '../services/auth_service.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../services/session_store.dart';
import '../utils/contacto.dart';
import 'ui/ui.dart';

/// Cómo se muestra cada perfil
const perfilesCuenta = {
  'cliente': (Icons.shopping_bag_rounded, 'Cliente', 'Pedir a los negocios'),
  'vendedor': (Icons.storefront_rounded, 'Negocio', 'Atender los pedidos de tu negocio'),
  'repartidor': (Icons.delivery_dining_rounded, 'Repartidor', 'Llevar pedidos'),
  'administrador': (Icons.admin_panel_settings_rounded, 'Administrador', 'Panel de ValleXpress'),
};

/// Pide la contraseña de la otra cuenta (la primera vez que se cambia a ella en este celular)
Future<String?> _pedirClave(BuildContext context, String perfil) {
  final clave = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Entrar como ${perfilesCuenta[perfil]?.$2 ?? perfil}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Escribe la contraseña de esa cuenta. Solo te la pedimos la primera vez en este celular.'),
        const SizedBox(height: 12),
        TextField(
          controller: clave,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, clave.text), child: const Text('Entrar')),
      ],
    ),
  );
}

/// Cambia a otra cuenta de la persona y abre su inicio. La cuenta actual queda abierta para volver.
/// Antes de pedir la contraseña se consulta el estado de esa cuenta AHORA (pudo bloquearse hace un momento): si está
/// bloqueada se avisa y no se deja escribir la clave. Si se bloquea mientras la escribe (muchos intentos), igual.
Future<void> cambiarDeCuenta(BuildContext context, {required String usuario, required String tipoUsuario}) async {
  final auth = context.read<AuthProvider>();
  final navegador = Navigator.of(context);
  Future<void> avisar(String estado, DateTime? hasta) =>
      context.mounted ? avisarCuentaBloqueada(context, usuario: usuario, perfil: tipoUsuario, estado: estado, hasta: hasta) : Future.value();
  try {
    // Estado de esa cuenta en este momento
    final actual = (await auth.misCuentas().catchError((_) => <Map<String, dynamic>>[])).where((c) => c['usuario'] == usuario).firstOrNull;
    final estado = '${actual?['estado'] ?? 'activo'}';
    final hasta = DateTime.tryParse('${actual?['hasta'] ?? ''}')?.toLocal();
    final guardada = await CuentasGuardadas.de(usuario);
    // Bloqueada: no se pide la clave. Con el bloqueo temporal, si ya tenía la sesión abierta aquí, entra igual
    // (el bloqueo es solo para escribir la contraseña).
    if (estado == 'bloqueado' || estado == 'inactivo' || (estado == 'temporal' && guardada == null)) return avisar(estado, hasta);

    var listo = await auth.cambiarACuenta(usuario);
    if (!listo) {
      if (!context.mounted) return;
      final clave = await _pedirClave(context, tipoUsuario);
      if (clave == null || clave.isEmpty) return;
      listo = await auth.cambiarACuenta(usuario, clave: clave, tipoUsuario: tipoUsuario);
    }
    if (!listo) return;
    HapticFeedback.mediumImpact();
    navegador.pushNamedAndRemoveUntil(AppConstants.homeRoute, (_) => false);
  } on ErrorLogin catch (e) {
    // Se bloqueó justo ahora (5 claves incorrectas) o la desactivó el administrador
    if (e.bloqueoTemporal) return avisar('temporal', DateTime.now().add(Duration(seconds: e.segundos ?? 900)));
    if (e.desactivada) return avisar(e.estatus == 'inactivo' ? 'inactivo' : 'bloqueado', null);
    if (context.mounted) mostrarError(context, e.mensaje);
  } catch (e) {
    if (context.mounted) mostrarError(context, textoDeError(e));
  }
}

/// La otra cuenta no puede entrar: un mensaje corto con el usuario y cómo resolverlo, sin dejar escribir la clave.
///   temporal  → se bloqueó por contraseñas incorrectas: esperar o recuperar la contraseña (la desbloquea)
///   bloqueado → la bloqueó ValleXpress: pedir el desbloqueo a soporte
///   inactivo  → está dada de baja: pedir a soporte que la reactive
Future<void> avisarCuentaBloqueada(BuildContext context, {required String usuario, required String perfil, required String estado, DateTime? hasta}) async {
  final auth = context.read<AuthProvider>();
  final correo = auth.usuario?['email']?.toString();
  final nombre = perfilesCuenta[perfil]?.$2.toLowerCase() ?? perfil;
  final hora = hasta == null ? null : '${hasta.hour.toString().padLeft(2, '0')}:${hasta.minute.toString().padLeft(2, '0')}';
  final soporte = await AuthService().soporteContacto().catchError((_) => (whatsapp: null, correo: null));
  if (!context.mounted) return;
  final (icono, color, titulo, texto) = switch (estado) {
    'temporal' => (
        Icons.lock_clock_rounded,
        AppTheme.warningColor,
        'Tu cuenta de $nombre ($usuario) está bloqueada',
        'Por varios intentos con la contraseña incorrecta. ${hora != null ? 'Podrás entrar a las $hora' : 'Espera unos minutos'} o recupera tu contraseña.',
      ),
    'inactivo' => (Icons.person_off_rounded, AppTheme.errorColor, 'Tu cuenta de $nombre ($usuario) está dada de baja', 'Pide a soporte que la reactive.'),
    _ => (Icons.block_rounded, AppTheme.errorColor, 'Tu cuenta de $nombre ($usuario) está bloqueada', 'Solicita el desbloqueo a soporte.'),
  };
  final mensaje = 'Hola, mi cuenta de $nombre de ValleXpress ($usuario) está bloqueada. ¿Me ayudan?';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icono, size: 44, color: color),
          const SizedBox(height: 10),
          Text(titulo, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(texto, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 18),
          if (estado == 'temporal') ...[
            BotonValle(
              texto: 'Recuperar mi contraseña',
              icono: Icons.lock_reset_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(correo: correo)));
              },
            ),
            const SizedBox(height: 12),
          ],
          if (soporte.whatsapp != null || soporte.correo != null) ...[
            Text('Contacta a soporte', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (soporte.whatsapp != null) ...[
                _Contacto(icono: Icons.chat_rounded, texto: 'WhatsApp', onTap: () => abrirWhatsapp(ctx, soporte.whatsapp!, mensaje: mensaje)),
                _Contacto(icono: Icons.call_rounded, texto: 'Llamar', onTap: () => llamar(ctx, soporte.whatsapp!)),
              ],
              if (soporte.correo != null)
                _Contacto(icono: Icons.mail_outline_rounded, texto: 'Correo', onTap: () => escribirASoporte(ctx, soporte.correo!, asunto: 'Mi cuenta $usuario está bloqueada')),
            ]),
          ],
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ]),
      ),
    ),
  );
}

class _Contacto extends StatelessWidget {
  const _Contacto({required this.icono, required this.texto, required this.onTap});

  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          IconButton.filledTonal(onPressed: onTap, icon: Icon(icono)),
          Text(texto, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// "Tus cuentas" en el perfil: las otras cuentas de la persona (cliente, negocio, repartidor) para cambiar con un
/// toque. Si tiene una sola, invita a crear otro perfil con su misma cédula y correo.
class TusCuentas extends StatefulWidget {
  const TusCuentas({super.key});

  @override
  State<TusCuentas> createState() => _TusCuentasState();
}

class _TusCuentasState extends State<TusCuentas> with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _cuentas;
  String? _cambiando; // la cuenta a la que se está cambiando (solo ella muestra la carga)

  // El estado de las cuentas cambia solo (un bloqueo temporal vence, el admin desbloquea): se refresca cada 30 s, al
  // volver a la app y justo cuando vence un bloqueo temporal
  Timer? _cada;
  Timer? _alVencer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recargar();
    _cada = Timer.periodic(const Duration(seconds: 30), (_) => _recargar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cada?.cancel();
    _alVencer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _recargar();
  }

  void _recargar() {
    context.read<AuthProvider>().misCuentas().then((c) {
      if (!mounted) return;
      setState(() => _cuentas = c);
      // Vuelve a consultar en el segundo en que vence el bloqueo temporal más próximo
      _alVencer?.cancel();
      final vencimientos = [
        for (final x in c)
          if (DateTime.tryParse('${x['hasta'] ?? ''}') case final h?) h.toLocal().difference(DateTime.now()),
      ].where((d) => !d.isNegative).toList()
        ..sort();
      if (vencimientos.isNotEmpty) _alVencer = Timer(vencimientos.first + const Duration(seconds: 2), _recargar);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final otras = (_cuentas ?? []).where((c) => c['actual'] != true).toList();
    if (_cuentas == null || otras.isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const EncabezadoSeccion('Tus otras cuentas', subtitulo: 'Cambia sin cerrar sesión'),
        TarjetaValle(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, cuenta) in otras.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.borde),
                ListTile(
                  enabled: _cambiando == null,
                  leading: Icon(perfilesCuenta[cuenta['tipoUsuario']]?.$1 ?? Icons.person_rounded, color: (cuenta['estado'] ?? 'activo') == 'activo' ? c.primario : c.textoSuave),
                  title: Text('Entrar como ${perfilesCuenta[cuenta['tipoUsuario']]?.$2 ?? cuenta['tipoUsuario']}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text(switch (cuenta['estado']) {
                    'temporal' => 'Bloqueada unos minutos por contraseñas incorrectas',
                    'bloqueado' => 'Bloqueada por ValleXpress',
                    'inactivo' => 'Dada de baja',
                    _ => '${perfilesCuenta[cuenta['tipoUsuario']]?.$3 ?? ''} · ${cuenta['usuario']}',
                  }, style: (cuenta['estado'] ?? 'activo') == 'activo' ? null : const TextStyle(color: AppTheme.errorColor)),
                  trailing: _cambiando == '${cuenta['usuario']}'
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon((cuenta['estado'] ?? 'activo') == 'activo' ? Icons.swap_horiz_rounded : Icons.lock_rounded),
                  onTap: () async {
                    setState(() => _cambiando = '${cuenta['usuario']}');
                    await cambiarDeCuenta(context, usuario: '${cuenta['usuario']}', tipoUsuario: '${cuenta['tipoUsuario']}');
                    if (!mounted) return;
                    setState(() => _cambiando = null);
                    _recargar(); // por si cambió su estado (se bloqueó por intentos, etc.)
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// En el login: las cuentas que siguen abiertas en este celular, para entrar con un toque.
/// [alNecesitarClave] recibe el usuario cuando esa sesión ya no sirve (hay que escribir la contraseña).
class CuentasEnEsteCelular extends StatefulWidget {
  const CuentasEnEsteCelular({super.key, required this.alNecesitarClave});

  final void Function(CuentaGuardada cuenta) alNecesitarClave;

  @override
  State<CuentasEnEsteCelular> createState() => _CuentasEnEsteCelularState();
}

class _CuentasEnEsteCelularState extends State<CuentasEnEsteCelular> {
  List<CuentaGuardada> _cuentas = [];
  String? _entrando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final c = await context.read<AuthProvider>().cuentasGuardadas();
    if (mounted) setState(() => _cuentas = c);
  }

  Future<void> _entrar(CuentaGuardada cuenta) async {
    setState(() => _entrando = cuenta.usuario);
    final navegador = Navigator.of(context);
    try {
      final ok = await context.read<AuthProvider>().entrarConGuardada(cuenta.usuario);
      if (ok) {
        navegador.pushNamedAndRemoveUntil(AppConstants.homeRoute, (_) => false);
        return;
      }
      widget.alNecesitarClave(cuenta);
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _entrando = null);
    }
  }

  Future<void> _olvidar(CuentaGuardada cuenta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar esta cuenta del celular?'),
        content: Text('Se cierra la sesión de ${cuenta.usuario} en este celular y deja de recibir sus avisos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AuthProvider>().olvidarCuenta(cuenta.usuario);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    if (_cuentas.isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Continuar con una cuenta de este celular', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final cuenta in _cuentas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TarjetaValle(
                onTap: _entrando == null ? () => _entrar(cuenta) : null,
                child: Row(children: [
                  Icon(perfilesCuenta[cuenta.tipoUsuario]?.$1 ?? Icons.person_rounded, color: c.primario, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${cuenta.nombre.isEmpty ? cuenta.usuario : cuenta.nombre} · ${perfilesCuenta[cuenta.tipoUsuario]?.$2 ?? cuenta.tipoUsuario}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(cuenta.usuario, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                    ]),
                  ),
                  if (_entrando == cuenta.usuario)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(tooltip: 'Quitar del celular', onPressed: () => _olvidar(cuenta), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
            ),
          Row(children: [
            Expanded(child: Divider(color: c.borde)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('o entra con otra', style: tema.bodySmall)),
            Expanded(child: Divider(color: c.borde)),
          ]),
        ],
      ),
    );
  }
}
