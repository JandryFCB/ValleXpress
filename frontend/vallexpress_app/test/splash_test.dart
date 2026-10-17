// La pantalla de arranque ocupa toda la pantalla y el logo queda en el centro exacto (como el de Android).
// Antes el contenedor se encogía al tamaño del logo y este aparecía arriba a la izquierda cuando la app tardaba.
//   flutter test test/splash_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/screens/splash_screen.dart';

void main() {
  testWidgets('el logo del arranque queda en el centro de la pantalla', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const SplashScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
    final logo = tester.getCenter(find.byType(Image).first);
    expect(logo.dx, closeTo(pantalla.width / 2, 2));
    expect(logo.dy, closeTo(pantalla.height / 2, 2));
    await tester.pumpWidget(const SizedBox()); // detiene las animaciones en bucle
  });
}
