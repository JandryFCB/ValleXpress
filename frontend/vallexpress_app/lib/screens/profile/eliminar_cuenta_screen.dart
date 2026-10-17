import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_error.dart';
import '../../widgets/ui/ui.dart';
import '../legal/documento_legal_screen.dart';

/// Eliminar la cuenta (derecho de eliminación; Google Play lo exige dentro de la app). Explica qué se borra y qué se
/// conserva, pide la contraseña y una confirmación. El servidor no la deja eliminar con un pedido en curso ni, a un
/// negocio, con comisiones por pagar: ese motivo se muestra tal cual.
class EliminarCuentaScreen extends StatefulWidget {
  const EliminarCuentaScreen({super.key});

  @override
  State<EliminarCuentaScreen> createState() => _EliminarCuentaScreenState();
}

class _EliminarCuentaScreenState extends State<EliminarCuentaScreen> {
  final _clave = TextEditingController();
  bool _entiende = false;
  bool _eliminando = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _eliminar() async {
    FocusScope.of(context).unfocus();
    if (_clave.text.isEmpty) return mostrarError(context, 'Escribe tu contraseña para confirmar');
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta definitivamente?'),
        content: const Text('Borraremos tus datos personales y no podrás recuperarla.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('Eliminar')),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    setState(() => _eliminando = true);
    final navegador = Navigator.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthProvider>().eliminarCuenta(_clave.text);
      navegador.pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
      mensajero.showSnackBar(const SnackBar(content: Text('Tu cuenta fue eliminada. Gracias por haber usado ValleXpress')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _eliminando = false);
      mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final rol = context.read<AuthProvider>().usuario?['tipoUsuario']?.toString() ?? 'cliente';
    Widget fila(IconData icono, String texto, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icono, size: 20, color: color ?? c.textoSuave),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: tema.bodyMedium)),
          ]),
        );

    return FondoValle(
      appBar: AppBar(title: const Text('Eliminar mi cuenta')),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TarjetaValle(
            color: AppTheme.errorColor.withValues(alpha: 0.08),
            colorBorde: AppTheme.errorColor.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Qué borramos', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.errorColor)),
                const SizedBox(height: 10),
                fila(Icons.person_off_rounded, 'Tu nombre, cédula, correo, teléfono y foto de perfil.', color: AppTheme.errorColor),
                fila(Icons.location_off_rounded, 'Tus direcciones guardadas.', color: AppTheme.errorColor),
                if (rol == 'repartidor') fila(Icons.two_wheeler_rounded, 'Tu vehículo, placa y los recorridos de tus entregas.', color: AppTheme.errorColor),
                if (rol == 'vendedor') fila(Icons.storefront_rounded, 'Tu negocio deja de aparecer en la app.', color: AppTheme.errorColor),
                fila(Icons.devices_rounded, 'Se cierra tu sesión en todos tus equipos.', color: AppTheme.errorColor),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TarjetaValle(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Qué conservamos', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                fila(Icons.receipt_long_rounded, 'Los pedidos${rol == 'vendedor' ? ', ventas y comisiones' : ''}, sin tus datos de contacto, porque son registros contables que exige la ley.'),
                fila(Icons.block_rounded, rol == 'vendedor'
                    ? 'No puedes eliminarla con un pedido en curso o con comisiones por pagar.'
                    : 'No puedes eliminarla mientras tengas un pedido en curso.'),
                GestureDetector(
                  onTap: () => abrirDocumentoLegal(context, 'privacidad'),
                  child: Text('Más detalles en la Política de privacidad', style: tema.bodySmall?.copyWith(color: c.primario, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          CampoValle(controller: _clave, etiqueta: 'Tu contraseña', icono: Icons.lock_outline_rounded, esClave: true, accion: TextInputAction.done, enabled: !_eliminando),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _entiende,
            onChanged: _eliminando ? null : (v) => setState(() => _entiende = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Entiendo que esto no se puede deshacer'),
          ),
          const SizedBox(height: 8),
          BotonValle(texto: 'Eliminar mi cuenta', icono: Icons.delete_forever_rounded, tipo: TipoBoton.peligro, cargando: _eliminando, onPressed: _entiende ? _eliminar : null),
        ],
      ),
    );
  }
}
