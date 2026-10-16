import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pedido.dart';
import '../widgets/ui/ui.dart';

/// Abre el marcador del teléfono con el número (no llama solo: la persona confirma)
Future<void> llamar(BuildContext context, String telefono) async {
  final uri = Uri(scheme: 'tel', path: telefono.replaceAll(RegExp(r'[^\d+]'), ''));
  if (!await launchUrl(uri) && context.mounted) mostrarError(context, 'No se pudo abrir el teléfono');
}

/// Abre el correo para escribir a soporte; si no hay app de correo, copia la dirección
Future<void> escribirASoporte(BuildContext context, String correo, {String asunto = 'Ayuda con mi cuenta de ValleXpress'}) async {
  final abierto = await launchUrl(Uri(scheme: 'mailto', path: correo, queryParameters: {'subject': asunto}));
  if (!abierto && context.mounted) {
    await Clipboard.setData(ClipboardData(text: correo));
    if (context.mounted) mostrarMensaje(context, 'Copiamos el correo de soporte: $correo');
  }
}

/// Abre la ruta hacia un punto en Google Maps (o en la app de mapas que haya)
Future<void> abrirEnMapas(BuildContext context, Punto destino) async {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${destino.latitud},${destino.longitud}&travelmode=driving');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) mostrarError(context, 'No se pudo abrir el mapa');
}

/// Distancia en km entre dos puntos, en línea recta (fórmula del haversine)
double distanciaKm(Punto a, Punto b) {
  double rad(double g) => g * pi / 180;
  final dLat = rad(b.latitud - a.latitud);
  final dLng = rad(b.longitud - a.longitud);
  final h = pow(sin(dLat / 2), 2) + cos(rad(a.latitud)) * cos(rad(b.latitud)) * pow(sin(dLng / 2), 2);
  return 6371 * 2 * asin(sqrt(h));
}

/// "850 m" · "2.4 km"
String textoDistancia(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
