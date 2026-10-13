// La pantalla de login se dibuja sin errores en modo claro y oscuro, y el selector de tema funciona.
//   flutter test test/login_temas_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/providers/auth_provider.dart';
import 'package:vallexpress_app/providers/tema_provider.dart';
import 'package:vallexpress_app/screens/auth/login_screen.dart';
import 'package:vallexpress_app/services/session_store.dart';

Widget _app(ThemeMode modo) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TemaProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: modo,
        home: const LoginScreen(),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionStore.almacen = AlmacenMemoria();
    SessionStore.reiniciarCache();
  });

  for (final modo in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('el login se dibuja bien en modo ${modo.name}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(modo));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Bienvenido de vuelta'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Crear una cuenta'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final contexto = tester.element(find.byType(LoginScreen));
      final esperado = modo == ThemeMode.dark ? AppTheme.backgroundColor : const Color(0xFFF4F8F5);
      expect(contexto.colores.fondo, esperado);
    });
  }

  testWidgets('campos vacíos muestran los mensajes de validación', (tester) async {
    await tester.pumpWidget(_app(ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(find.text('Escribe tu correo o tu usuario'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  test('el tema elegido se guarda y se recupera', () async {
    final tema = TemaProvider();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(tema.modo, TemaProvider.porDefecto);
    await tema.cambiar(ThemeMode.light);

    final otro = TemaProvider();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(otro.modo, ThemeMode.light, reason: 'la preferencia debe sobrevivir al reinicio de la app');
  });
}
