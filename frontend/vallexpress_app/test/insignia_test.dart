// Una insignia con un texto largo (un motivo de cancelación) no se sale del borde: baja de línea.
//   flutter test test/insignia_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/widgets/ui/ui.dart';

const _largo = 'Cancelado automáticamente: ningún repartidor lo recogió a tiempo y el negocio ya cerró por hoy';

Widget _app(Widget hijo) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: hijo)));

void main() {
  Future<void> angosta(WidgetTester tester) async {
    tester.view.physicalSize = const Size(640, 1200); // 320 de ancho: el teléfono más angosto
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('en una columna (detalle del pedido): baja de línea sin desbordarse', (tester) async {
    await angosta(tester);
    await tester.pumpWidget(_app(const Column(children: [InsigniaValle(_largo, color: AppTheme.errorColor, icono: Icons.info_outline)])));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(InsigniaValle)).width, lessThanOrEqualTo(288));
    expect(tester.getSize(find.byType(InsigniaValle)).height, greaterThan(30), reason: 'ocupa más de una línea');
  });

  testWidgets('en una fila con algo al lado (tarjeta de pedido): tampoco se desborda', (tester) async {
    await angosta(tester);
    await tester.pumpWidget(_app(const Row(children: [
      Expanded(child: Align(alignment: Alignment.centerLeft, child: InsigniaValle('Juan Sebastián de la Torre Villavicencio viene por él', color: Colors.blue, icono: Icons.delivery_dining))),
      SizedBox(width: 8),
      Text('hace 5 min'),
    ])));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un texto corto ocupa solo lo que necesita', (tester) async {
    await angosta(tester);
    await tester.pumpWidget(_app(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [InsigniaValle('Abierto', color: Colors.green)])));
    expect(tester.getSize(find.byType(InsigniaValle)).width, lessThan(150), reason: 'no ocupa todo el ancho (288)');
  });
}
