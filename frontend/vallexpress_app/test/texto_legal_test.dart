// Los documentos legales llegan del servidor en bloques: se dibujan títulos, párrafos, listas (con sublista y notas)
// y la **negrita**, sin desbordarse en el teléfono más angosto.
//   flutter test test/texto_legal_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/models/legal.dart';
import 'package:vallexpress_app/screens/legal/documento_legal_screen.dart';

final _json = {
  'id': 'privacidad',
  'titulo': 'Política de privacidad',
  'version': '1.0',
  'vigencia': '2026-10-17',
  'bloques': [
    {'tipo': 'titulo', 'texto': '1. Responsable'},
    {'tipo': 'parrafo', 'texto': 'El responsable es **Jandry Franklin Cayapa Baque**, con cédula 1900830447.'},
    {
      'tipo': 'lista',
      'ordenada': false,
      'items': [
        {'texto': 'Entre usuarios de un mismo pedido:', 'sub': ['El negocio ve tu dirección', 'El repartidor ve tu teléfono'], 'notas': []},
        {'texto': 'Proveedores:', 'sub': [], 'notas': ['Algunos están fuera del Ecuador.']},
      ],
    },
    {'tipo': 'lista', 'ordenada': true, 'items': [{'texto': 'Eliges productos'}, {'texto': 'Confirmas'}]},
  ],
};

void main() {
  test('el modelo lee los bloques del servidor', () {
    final d = DocumentoLegal.desdeJson(_json);
    expect(d.esPrivacidad, isTrue);
    expect(d.vigencia, DateTime(2026, 10, 17));
    expect(d.bloques.map((b) => b.tipo), [TipoBloque.titulo, TipoBloque.parrafo, TipoBloque.lista, TipoBloque.lista]);
    expect(d.bloques[2].items.first.sub, hasLength(2));
    expect(d.bloques[2].items.last.notas.single, 'Algunos están fuera del Ecuador.');
    expect(d.bloques[3].ordenada, isTrue);
  });

  test('la negrita se separa en spans', () {
    final s = TextoLegal.spans('Hola **mundo** y **más**');
    expect(s.map((x) => x.text), ['Hola ', 'mundo', ' y ', 'más']);
    expect(s[1].style?.fontWeight, FontWeight.w800);
    expect(s[0].style, isNull);
  });

  testWidgets('se dibuja todo, numerado y sin desbordarse a 320 de ancho', (tester) async {
    tester.view.physicalSize = const Size(640, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final d = DocumentoLegal.desdeJson(_json);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: SingleChildScrollView(child: TextoLegal(bloques: d.bloques)))));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Jandry Franklin Cayapa Baque', findRichText: true), findsOneWidget);
    expect(find.textContaining('El repartidor ve tu teléfono', findRichText: true), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('–'), findsNWidgets(2));
  });
}
