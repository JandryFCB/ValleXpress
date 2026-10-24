import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ui/ui.dart';

/// El perfil de repartidor no funciona en la web: necesita el GPS en segundo plano y las notificaciones del celular
/// para recibir pedidos. Si entra desde el navegador se le pide usar la app de Android.
class SoloAppScreen extends StatelessWidget {
  const SoloAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return FondoValle(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delivery_dining_rounded, size: 72, color: c.primario),
                const SizedBox(height: 16),
                Text(
                  'Repartir es desde la app',
                  style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Para recibir y llevar pedidos necesitas la app de ValleXpress en tu celular Android: usa tu ubicación '
                  'mientras repartes y te avisa al instante cuando hay un pedido. Desde el navegador no se puede.',
                  style: tema.bodyMedium?.copyWith(color: c.textoSuave),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                BotonValle(
                  texto: 'Descargar la app para Android',
                  icono: Icons.android_rounded,
                  onPressed: () =>
                      launchUrl(Uri.parse('${AppConstants.serverUrl}/descargas/vallexpress.apk'), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil(AppConstants.loginRoute, (_) => false);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
