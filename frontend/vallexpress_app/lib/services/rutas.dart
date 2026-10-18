import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'api_http.dart' as http;

/// La ruta por las calles entre varios puntos (OSRM, el ruteador libre de OpenStreetMap). Es solo para dibujarla en
/// el mapa: si no responde, el mapa vuelve a la línea recta. Guarda las últimas rutas para no pedirlas de nuevo.
class Rutas {
  static final Map<String, List<LatLng>> _cache = {};

  static String _clave(List<LatLng> p) => p.map((x) => '${x.latitude.toStringAsFixed(4)},${x.longitude.toStringAsFixed(4)}').join(';');

  /// null = no se pudo (sin internet, servidor caído): dibujar la línea recta
  static Future<List<LatLng>?> calcular(List<LatLng> puntos) async {
    if (puntos.length < 2) return null;
    final clave = _clave(puntos);
    final guardada = _cache[clave];
    if (guardada != null) return guardada;
    final coords = puntos.map((x) => '${x.longitude},${x.latitude}').join(';');
    try {
      final res = await http
          .get(Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson'), headers: {'User-Agent': 'ec.vallexpress.app'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final rutas = (jsonDecode(res.body) as Map<String, dynamic>)['routes'] as List?;
      if (rutas == null || rutas.isEmpty) return null;
      final linea = [
        for (final c in (rutas.first['geometry']['coordinates'] as List)) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (_cache.length > 30) _cache.remove(_cache.keys.first);
      return _cache[clave] = linea;
    } catch (_) {
      return null;
    }
  }
}
