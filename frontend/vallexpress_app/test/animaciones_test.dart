// Pruebas de las piezas animadas del sistema de diseño (sin servidor).
//   flutter test test/animaciones_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/widgets/ui/ui.dart';

Widget _app(Widget hijo, {Brightness brillo = Brightness.dark}) => MaterialApp(
      theme: brillo == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: hijo),
    );

void main() {
  for (final brillo in Brightness.values) {
    testWidgets('esqueleto de carga en modo ${brillo.name}: se dibuja sin desbordes y el brillo corre', (t) async {
      await t.pumpWidget(_app(const EsqueletoLista(cantidad: 3, altoImagen: 130), brillo: brillo));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(Hueso), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Aparecer: empieza invisible y termina visible', (t) async {
    await t.pumpWidget(_app(const Aparecer(indice: 2, child: Text('hola'))));
    Opacity opacidad() => t.widget<Opacity>(find.ancestor(of: find.text('hola'), matching: find.byType(Opacity)).first);
    expect(opacidad().opacity, 0);
    await t.pumpAndSettle();
    expect(opacidad().opacity, 1);
  });

  testWidgets('BotonValle: responde al toque, vibra y muestra "cargando"', (t) async {
    final vibraciones = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (llamada) async {
      if (llamada.method == 'HapticFeedback.vibrate') vibraciones.add('${llamada.arguments}');
      return null;
    });
    var toques = 0;
    await t.pumpWidget(_app(BotonValle(texto: 'Pedir', onPressed: () => toques++)));
    await t.tap(find.text('Pedir'));
    await t.pumpAndSettle();
    expect(toques, 1);
    expect(vibraciones, isNotEmpty);

    await t.pumpWidget(_app(BotonValle(texto: 'Pedir', cargando: true, onPressed: () => toques++)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.byType(FilledButton), warnIfMissed: false);
    expect(toques, 1, reason: 'mientras carga no se puede volver a tocar');
  });

  testWidgets('PestanasAnimadas: cambia de pestaña sin perder lo escrito en la otra', (t) async {
    var indice = 0;
    late StateSetter fijar;
    await t.pumpWidget(_app(StatefulBuilder(builder: (_, s) {
      fijar = s;
      return PestanasAnimadas(indice: indice, children: const [TextField(key: Key('campo')), Text('perfil')]);
    })));
    await t.enterText(find.byKey(const Key('campo')), 'pizza');
    fijar(() => indice = 1);
    await t.pumpAndSettle();
    fijar(() => indice = 0);
    await t.pumpAndSettle();
    expect(find.text('pizza'), findsOneWidget);
  });

  testWidgets('Confeti: aparece sobre la pantalla y se quita solo', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    Confeti.lanzar(ctx);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(Confeti), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.byType(Confeti), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('IconoLatiendo y Rebote: cambian sin errores; DineroAnimado llega al valor final', (t) async {
    Widget armar(IconData icono, int n, double monto) => _app(Column(children: [
          IconoLatiendo(icono: icono, color: Colors.green),
          Rebote(valor: n, child: Text('$n')),
          DineroAnimado(monto),
        ]));
    await t.pumpWidget(armar(Icons.hourglass_top, 1, 8.5));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpWidget(armar(Icons.check, 2, 17));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('17.00'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
