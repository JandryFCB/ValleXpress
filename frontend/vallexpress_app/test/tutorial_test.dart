// El tutorial de bienvenida de cada perfil se ve completo en el teléfono más angosto, avanza y queda marcado
// como visto al terminar (no vuelve a salir).
//   flutter test test/tutorial_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/screens/inicio/tutorial_screen.dart';

void main() {
  for (final rol in ['cliente', 'vendedor', 'repartidor', 'administrador']) {
    testWidgets('$rol: todas las páginas sin desbordarse y queda visto al terminar', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(640, 1200); // 320 x 600
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      var terminado = false;
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: TutorialScreen(rol: rol, alTerminar: () => terminado = true)));
      await tester.pumpAndSettle();

      expect(await TutorialScreen.visto(rol), isFalse);
      // Avanza con "Siguiente" hasta "Empezar"
      for (var i = 0; i < 6 && find.text('Empezar').evaluate().isEmpty; i++) {
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Empezar'), findsOneWidget);
      await tester.tap(find.text('Empezar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(terminado, isTrue);
      expect(await TutorialScreen.visto(rol), isTrue);
    });
  }
}
