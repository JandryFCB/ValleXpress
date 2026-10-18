import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_error.dart';
import '../services/session_store.dart';
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
                  leading: Icon(perfilesCuenta[cuenta['tipoUsuario']]?.$1 ?? Icons.person_rounded, color: c.primario),
                  title: Text('Entrar como ${perfilesCuenta[cuenta['tipoUsuario']]?.$2 ?? cuenta['tipoUsuario']}', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('${perfilesCuenta[cuenta['tipoUsuario']]?.$3 ?? ''} · ${cuenta['usuario']}'),
                  trailing: _cambiando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.swap_horiz_rounded),
                  onTap: () async {
                    setState(() => _cambiando = true);
                    await cambiarDeCuenta(context, usuario: '${cuenta['usuario']}', tipoUsuario: '${cuenta['tipoUsuario']}');
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
