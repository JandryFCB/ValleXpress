import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../config/navegacion.dart';
import 'api_http.dart' as http;

/// Aviso de versión nueva (mientras la app se reparte como APK, fuera de las tiendas). Al abrir la app compara su
/// número de compilación (el "+N" de pubspec.yaml) con el del servidor:
///   * menor que la mínima -> obliga a actualizar (no se puede cerrar)
///   * menor que la última  -> ofrece actualizar (una vez por apertura)
/// El botón abre la descarga de la APK en el navegador. Sin conexión no hace nada.
class VersionApp {
  static bool _revisado = false;

  /// Versión instalada, para mostrarla en Configuración ("1.0.4")
  static Future<String> texto() async {
    final p = await PackageInfo.fromPlatform();
    return p.version; // solo la versión (1.0.4); el número de compilación es interno
  }

  static Future<void> revisar() async {
    if (_revisado || kIsWeb) return;
    _revisado = true;
    try {
      final instalada = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      final res = await http.get(Uri.parse('${AppConstants.baseUrl}/app/version'));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final ultima = (j['ultima'] as num?)?.toInt() ?? 0;
      final minima = (j['minima'] as num?)?.toInt() ?? 0;
      final url = '${j['url'] ?? ''}';
      if (url.isEmpty || instalada >= ultima) return;
      _mostrar(obligatoria: instalada < minima, url: url, novedades: '${j['novedades'] ?? ''}');
    } catch (_) {
      // sin conexión o servidor caído: se revisa en la próxima apertura
    }
  }

  static void _mostrar({required bool obligatoria, required String url, required String novedades}) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog<void>(
      context: ctx,
      barrierDismissible: !obligatoria,
      builder: (dCtx) => PopScope(
        canPop: !obligatoria,
        child: AlertDialog(
          icon: const Icon(Icons.system_update_rounded, size: 40),
          title: Text(obligatoria ? 'Actualiza ValleXpress' : 'Hay una versión nueva'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(obligatoria
                  ? 'Esta versión ya no funciona. Descarga la nueva para seguir usando la app.'
                  : 'Descárgala para tener las últimas mejoras.'),
              if (novedades.trim().isNotEmpty) ...[const SizedBox(height: 10), Text(novedades.trim(), style: Theme.of(dCtx).textTheme.bodySmall)],
              const SizedBox(height: 10),
              Text('Al terminar la descarga, ábrela e instala. Tus datos se conservan.', style: Theme.of(dCtx).textTheme.bodySmall),
            ],
          ),
          actions: [
            if (!obligatoria) TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Más tarde')),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Descargar'),
            ),
          ],
        ),
      ),
    );
  }
}
