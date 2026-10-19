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
Future<void> cambiarDeCuenta(BuildContext context, {required String usuario, required String tipoUsuario}) async {
  final auth = context.read<AuthProvider>();
  final navegador = Navigator.of(context);
  try {
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
  } catch (e) {
    if (context.mounted) mostrarError(context, textoDeError(e));
  }
}

/// La otra cuenta no puede entrar: se explica por qué y qué hacer, en vez de pedir una contraseña que no sirve.
///   temporal  → se bloqueó sola por contraseñas incorrectas: esperar o recuperar la contraseña (la desbloquea)
///   bloqueado → la bloqueó el administrador: escribir a soporte
///   inactivo  → está dada de baja: escribir a soporte para reactivarla
Future<void> _avisarCuentaBloqueada(BuildContext context, {required String perfil, required String estado, DateTime? hasta}) {
  final auth = context.read<AuthProvider>();
  final correo = auth.usuario?['email']?.toString();
  final nombre = perfilesCuenta[perfil]?.$2.toLowerCase() ?? perfil;
  final hora = hasta == null ? null : '${hasta.hour.toString().padLeft(2, '0')}:${hasta.minute.toString().padLeft(2, '0')}';
  final (icono, titulo, texto) = switch (estado) {
    'temporal' => (
        Icons.lock_clock_rounded,
        'Tu cuenta de $nombre está bloqueada por unos minutos',
        'Se escribió mal la contraseña varias veces. Podrás entrar${hora != null ? ' a las $hora' : ' en unos minutos'}, o recupera tu contraseña ahora: al cambiarla se desbloquea al instante.',
      ),
    'inactivo' => (Icons.person_off_rounded, 'Tu cuenta de $nombre está dada de baja', 'Si quieres volver a usarla, escríbenos y la reactivamos.'),
    _ => (Icons.block_rounded, 'Tu cuenta de $nombre está bloqueada', 'El equipo de ValleXpress la bloqueó. Escríbenos para revisar tu caso.'),
  };
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icono, size: 44, color: estado == 'temporal' ? AppTheme.warningColor : AppTheme.errorColor),
          const SizedBox(height: 10),
          Text(titulo, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(texto, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 20),
          if (estado == 'temporal')
            BotonValle(
              texto: 'Recuperar mi contraseña',
              icono: Icons.lock_reset_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(correo: correo)));
              },
            ),
          if (estado == 'temporal') const SizedBox(height: 10),
          BotonValle(
            texto: 'Escribir a soporte',
            icono: Icons.support_agent_rounded,
            tipo: estado == 'temporal' ? TipoBoton.secundario : TipoBoton.principal,
            onPressed: () async {
              Navigator.pop(ctx);
              final soporte = await AuthService().soporteContacto();
              if (!context.mounted) return;
              if (soporte.whatsapp != null) {
                await abrirWhatsapp(context, soporte.whatsapp!, mensaje: 'Hola, mi cuenta de $nombre de ValleXpress (${auth.usuario?['email'] ?? ''}) está bloqueada. ¿Me ayudan?');
              } else if (soporte.correo != null) {
                await escribirASoporte(context, soporte.correo!, asunto: 'Mi cuenta de $nombre está bloqueada');
              } else {
                mostrarMensaje(context, 'Escríbenos desde la página de ValleXpress');
              }
            },
          ),
        ]),
      ),
    ),
  );
}

/// "Tus cuentas" en el perfil: las otras cuentas de la persona (cliente, negocio, repartidor) para cambiar con un
/// toque. Si tiene una sola, invita a crear otro perfil con su misma cédula y correo.
class TusCuentas extends StatefulWidget {
  const TusCuentas({super.key});

  @override
  State<TusCuentas> createState() => _TusCuentasState();
}

class _TusCuentasState extends State<TusCuentas> {
  List<Map<String, dynamic>>? _cuentas;
  bool _cambiando = false;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().misCuentas().then((c) {
      if (mounted) setState(() => _cuentas = c);
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
                  enabled: !_cambiando,
                  leading: Icon(perfilesCuenta[cuenta['tipoUsuario']]?.$1 ?? Icons.person_rounded, color: (cuenta['estado'] ?? 'activo') == 'activo' ? c.primario : c.textoSuave),
                  title: Text('Entrar como ${perfilesCuenta[cuenta['tipoUsuario']]?.$2 ?? cuenta['tipoUsuario']}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text(switch (cuenta['estado']) {
                    'temporal' => 'Bloqueada unos minutos por contraseñas incorrectas',
                    'bloqueado' => 'Bloqueada por ValleXpress',
                    'inactivo' => 'Dada de baja',
                    _ => '${perfilesCuenta[cuenta['tipoUsuario']]?.$3 ?? ''} · ${cuenta['usuario']}',
                  }, style: (cuenta['estado'] ?? 'activo') == 'activo' ? null : const TextStyle(color: AppTheme.errorColor)),
                  trailing: _cambiando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon((cuenta['estado'] ?? 'activo') == 'activo' ? Icons.swap_horiz_rounded : Icons.lock_rounded),
                  onTap: () async {
                    final estado = '${cuenta['estado'] ?? 'activo'}';
                    final usuario = '${cuenta['usuario']}';
                    // Bloqueada: se explica qué hacer. Con el bloqueo temporal, si ya tenía la sesión abierta en este
                    // celular sí puede entrar (el bloqueo es solo para escribir la contraseña).
                    if (estado != 'activo' && !(estado == 'temporal' && await CuentasGuardadas.de(usuario) != null)) {
                      if (!context.mounted) return;
                      return _avisarCuentaBloqueada(context, perfil: '${cuenta['tipoUsuario']}', estado: estado, hasta: DateTime.tryParse('${cuenta['hasta'] ?? ''}')?.toLocal());
                    }
                    if (!context.mounted) return;
                    setState(() => _cambiando = true);
                    await cambiarDeCuenta(context, usuario: usuario, tipoUsuario: '${cuenta['tipoUsuario']}');
                    if (mounted) setState(() => _cambiando = false);
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
