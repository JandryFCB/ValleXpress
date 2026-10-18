import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vallexpress_app/widgets/mapa_pedido.dart';

void main() {
  // Una calle de Yantzaza en "L": hacia el este y luego hacia el norte
  const ruta = [LatLng(-3.8277, -78.7593), LatLng(-3.8277, -78.7560), LatLng(-3.8240, -78.7560)];

  test('sobre la ruta: a menos de 40 m y en el tramo correcto', () {
    final c = cercaniaARuta(ruta, const LatLng(-3.82775, -78.7575)); // ~5 m al sur del primer tramo
    expect(c.metros, lessThan(10));
    expect(c.tramo, 0);
    expect(cercaniaARuta(ruta, const LatLng(-3.8260, -78.75605)).tramo, 1);
  });

  test('tomó otra calle: más de 40 m de la ruta (hay que recalcular)', () {
    final c = cercaniaARuta(ruta, const LatLng(-3.8268, -78.7580)); // una cuadra al norte del primer tramo (~100 m)
    expect(c.metros, greaterThan(40));
  });
}
