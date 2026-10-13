import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Datos del equipo que se mandan al iniciar sesión. El servidor los guarda en la sesión para poder mostrar
/// "dispositivos con sesión iniciada". Nunca debe romper el login: si algo falla, se manda un valor genérico.
Future<Map<String, String>> datosDispositivo() async {
  final plataforma = kIsWeb
      ? 'WEB'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'ANDROID',
          TargetPlatform.iOS => 'IOS',
          _ => 'WEB',
        };

  String nombre = 'ValleXpress';
  try {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      nombre = (await info.webBrowserInfo).browserName.name;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await info.androidInfo;
      nombre = '${a.brand} ${a.model}'.trim();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      nombre = (await info.iosInfo).utsname.machine;
    }
  } catch (_) {
    // se queda con el nombre genérico
  }
  return {'dispositivo': nombre.length > 100 ? nombre.substring(0, 100) : nombre, 'plataforma': plataforma};
}
