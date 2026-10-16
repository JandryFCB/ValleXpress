// Pantalla de "cuenta en revisión": cada estado muestra lo suyo (pasos, motivo, botones) en claro y oscuro.
//   flutter test test/panel_aprobacion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/widgets/panel_aprobacion.dart';

Widget _app(Widget hijo, {ThemeMode modo = ThemeMode.dark}) =>
    MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: modo, home: Scaffold(body: hijo));

PanelAprobacion _panel(String estado, {String? motivo, TipoSolicitud tipo = TipoSolicitud.negocio, Future<void> Function()? onPedir, VoidCallback? onMientras}) =>
    PanelAprobacion(
      tipo: tipo,
      aprobacion: estado,
      motivo: motivo,
      soporte: 'soporte@vallexpress.test',
      textoMientras: 'Armar mi menú',
      onMientras: onMientras ?? () {},
      textoCorregir: 'Corregir mi negocio',
      onCorregir: () {},
      onPedirRevision: onPedir ?? () async {},
      onActualizar: () async {},
    );

void main() {
  Future<void> dibujar(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pump(const Duration(milliseconds: 600)); // termina la entrada (Aparecer)
  }

  for (final modo in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('pendiente (${modo.name}): pasos y qué adelantar, sin pedir revisión', (tester) async {
      var mientras = 0;
      await dibujar(tester, _app(_panel('pendiente', onMientras: () => mientras++), modo: modo));
      expect(find.text('Estamos revisando tu solicitud'), findsOneWidget);
      expect(find.text('Solicitud enviada'), findsOneWidget);
      expect(find.text('Revisión del equipo'), findsOneWidget);
      expect(find.text('¡A vender!'), findsOneWidget);
      expect(find.text('Pedir nueva revisión'), findsNothing);
      await tester.tap(find.text('Armar mi menú'));
      expect(mientras, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rechazado: motivo, corregir y pedir nueva revisión', (tester) async {
    var pedidas = 0;
    await dibujar(tester, _app(_panel('rechazado', motivo: 'Falta el RUC del local', onPedir: () async => pedidas++)));
    expect(find.text('Tu solicitud no fue aprobada'), findsOneWidget);
    expect(find.text('Falta el RUC del local'), findsOneWidget);
    expect(find.text('Corregir mi negocio'), findsOneWidget);
    expect(find.text('Contactar a soporte'), findsOneWidget);
    await tester.tap(find.text('Pedir nueva revisión'));
    await tester.pump();
    expect(pedidas, 1);
    await tester.pump(const Duration(seconds: 5)); // se va el mensaje de confirmación
  });

  testWidgets('suspendido (repartidor): motivo y soporte, sin pedir revisión', (tester) async {
    await dibujar(tester, _app(_panel('suspendido', motivo: 'Documentos vencidos', tipo: TipoSolicitud.repartidor)));
    expect(find.text('Tu cuenta de repartidor está suspendida'), findsOneWidget);
    expect(find.text('Documentos vencidos'), findsOneWidget);
    expect(find.text('Contactar a soporte'), findsOneWidget);
    expect(find.text('Pedir nueva revisión'), findsNothing);
    expect(find.text('Corregir mi negocio'), findsNothing);
  });
}
