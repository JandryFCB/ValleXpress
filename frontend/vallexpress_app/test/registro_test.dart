// Prueba del registro en 4 pasos con un servicio FALSO (no necesita backend):
//   flutter test test/registro_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vallexpress_app/config/theme.dart';
import 'package:vallexpress_app/providers/auth_provider.dart';
import 'package:vallexpress_app/screens/auth/register_screen.dart';
import 'package:vallexpress_app/services/auth_service.dart';
import 'package:vallexpress_app/services/session_store.dart';
import 'package:vallexpress_app/utils/validadores.dart';

class _FalsoAuth extends AuthService {
  bool cedulaExiste = false;
  bool emailExiste = false;
  int envios = 0;
  String codigoCorrecto = '123456';
  Map<String, bool>? perfiles; // null = sin conexión (se muestran todos)

  @override
  Future<Map<String, bool>?> perfilesRegistro() async => perfiles;

  @override
  Future<Map<String, dynamic>> checkCedula(String cedula) async => {'exists': cedulaExiste};
  @override
  Future<Map<String, dynamic>> checkEmail(String email) async => {'exists': emailExiste};
  @override
  Future<Map<String, dynamic>> sendEmailVerification(String email, String nombre, {String? fcmToken}) async {
    envios++;
    return {'message': 'ok'};
  }

  @override
  Future<Map<String, dynamic>> verifyEmailCode(String email, String code) async {
    if (code != codigoCorrecto) throw Exception('Código incorrecto');
    return {'verified': true};
  }
}

const cedulaValida = '1710034065';

Widget _app(_FalsoAuth falso, ThemeMode modo) => ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: modo,
        home: RegisterScreen(servicio: falso),
      ),
    );

/// Teléfono pequeño (360x640): si algo se desborda, la prueba falla con un error de layout
void _pantallaChica(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1280);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> _escribir(WidgetTester tester, String etiqueta, String texto) async {
  await tester.enterText(find.widgetWithText(TextFormField, etiqueta), texto);
  await tester.pump(const Duration(milliseconds: 600)); // deja pasar la espera de las comprobaciones
}

Future<void> _continuar(WidgetTester tester, {String texto = 'Continuar'}) async {
  await tester.tap(find.text(texto));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionStore.almacen = AlmacenMemoria();
    SessionStore.reiniciarCache();
  });

  group('Validadores', () {
    test('cédula ecuatoriana', () {
      expect(Validadores.cedula(cedulaValida), isTrue);
      expect(Validadores.cedula('1234567890'), isFalse);
      expect(Validadores.cedula('171003406'), isFalse);
      expect(Validadores.cedula('9910034065'), isFalse, reason: 'provincia inexistente');
    });
    test('teléfono, correo y placa', () {
      expect(Validadores.telefono('0991234567'), isTrue);
      expect(Validadores.telefono('099 123-4567'), isTrue);
      expect(Validadores.telefono('1991234567'), isFalse);
      expect(Validadores.email('a@b.com'), isTrue);
      expect(Validadores.email('a@b'), isFalse);
      expect(Validadores.placa('abc-123'), isTrue);
      expect(Validadores.placa('AB1234'), isTrue);
      expect(Validadores.placa('A1'), isFalse);
    });
    test('fuerza de la contraseña', () {
      expect(Validadores.fuerzaClave(''), 0);
      expect(Validadores.fuerzaClave('abc123'), 1);
      expect(Validadores.fuerzaClave('Secreto1234'), greaterThanOrEqualTo(3));
      expect(Validadores.fuerzaClave('Secreto1234!'), 4);
    });
  });

  for (final modo in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('paso 0 en modo ${modo.name}: muestra los 3 roles y pide elegir uno', (tester) async {
      _pantallaChica(tester);
      await tester.pumpWidget(_app(_FalsoAuth(), modo));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('¿Cómo vas a usar ValleXpress?'), findsOneWidget);
      for (final rol in ['Cliente', 'Vendedor', 'Repartidor']) {
        expect(find.text(rol), findsOneWidget);
      }
      await _continuar(tester);
      expect(find.text('Elige cómo vas a usar la app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('un perfil con el registro cerrado se ve apagado y no se puede elegir', (tester) async {
    _pantallaChica(tester);
    final falso = _FalsoAuth()..perfiles = {'cliente': true, 'vendedor': true, 'repartidor': false};
    await tester.pumpWidget(_app(falso, ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Por ahora no estamos recibiendo nuevas cuentas de este tipo.'), findsOneWidget);
    await tester.tap(find.text('Repartidor'));
    await _continuar(tester);
    expect(find.text('Elige cómo vas a usar la app'), findsOneWidget, reason: 'no quedó elegido');
    await tester.tap(find.text('Vendedor'));
    await _continuar(tester);
    expect(find.text('Cuéntanos de ti'), findsOneWidget, reason: 'los abiertos sí se pueden elegir');
    expect(tester.takeException(), isNull);
  });

  testWidgets('flujo completo de un vendedor hasta el último paso', (tester) async {
    _pantallaChica(tester);
    final falso = _FalsoAuth();
    await tester.pumpWidget(_app(falso, ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 400));

    // Paso 0: rol
    await tester.tap(find.text('Vendedor'));
    await tester.pump();
    await _continuar(tester);
    expect(find.text('Cuéntanos de ti'), findsOneWidget);

    // Paso 1: datos. Primero vacío -> avisa qué falta, de a una cosa
    await _continuar(tester);
    expect(find.text('Escribe tu nombre'), findsOneWidget);
    await _escribir(tester, 'Nombres', 'Luis');
    await _escribir(tester, 'Apellidos', 'Mora');
    await _escribir(tester, 'Cédula', '1234567890');
    expect(find.text('Cédula inválida: revisa los dígitos'), findsOneWidget);
    await _continuar(tester);
    expect(find.textContaining('La cédula no es válida'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Cédula'), '');
    await _escribir(tester, 'Cédula', cedulaValida);
    expect(find.text('Cédula válida'), findsOneWidget);
    await _escribir(tester, 'Teléfono móvil', '0991234567');
    expect(find.text('Teléfono válido'), findsOneWidget);
    await tester.ensureVisible(find.text('Tu negocio'));
    await _continuar(tester);
    expect(find.text('Escribe el nombre de tu negocio'), findsOneWidget);
    await _escribir(tester, 'Nombre del negocio', 'Pizzería Luis');
    await _continuar(tester);

    // Paso 2: correo
    expect(find.text('Verifica tu correo'), findsOneWidget);
    await _escribir(tester, 'Correo electrónico', 'luis@test.com');
    expect(find.text('Correo disponible'), findsOneWidget);
    await _continuar(tester);
    expect(find.text('Verifica tu correo con el código que te enviamos'), findsOneWidget);
    await tester.tap(find.text('Enviar código'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(falso.envios, 1);
    expect(find.text('Escribe el código'), findsOneWidget);
    expect(find.textContaining('Reenviar código en'), findsOneWidget, reason: 'hay que esperar antes de pedir otro código');

    await tester.enterText(find.byType(TextField).last, '111111');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Correo verificado'), findsNothing, reason: 'un código incorrecto no verifica');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Correo verificado'), findsWidgets);
    await _continuar(tester);

    // Paso 3: contraseña
    expect(find.text('Crea tu contraseña'), findsOneWidget);
    expect(find.text('Crear mi cuenta'), findsOneWidget);
    await _escribir(tester, 'Contraseña', 'abc');
    await _continuar(tester, texto: 'Crear mi cuenta');
    expect(find.textContaining('al menos 6 caracteres'), findsWidgets);
    await _escribir(tester, 'Contraseña', 'Secreto123');
    await _escribir(tester, 'Confirmar contraseña', 'Otra1234');
    expect(find.text('Las contraseñas no coinciden'), findsWidgets);
    await _escribir(tester, 'Confirmar contraseña', 'Secreto123');
    expect(find.text('Las contraseñas coinciden'), findsOneWidget);
    await _continuar(tester, texto: 'Crear mi cuenta');
    expect(find.text('Debes aceptar los términos y condiciones y la política de privacidad'), findsWidgets);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // libera los temporizadores
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('una cédula ya registrada bloquea el avance', (tester) async {
    _pantallaChica(tester);
    final falso = _FalsoAuth()..cedulaExiste = true;
    await tester.pumpWidget(_app(falso, ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cliente'));
    await tester.pump();
    await _continuar(tester);
    await _escribir(tester, 'Nombres', 'Ana');
    await _escribir(tester, 'Apellidos', 'Paz');
    await _escribir(tester, 'Cédula', cedulaValida);
    expect(find.text('Esta cédula ya está registrada'), findsOneWidget);
    await _escribir(tester, 'Teléfono móvil', '0991234567');
    await _continuar(tester);
    expect(find.text('Cuéntanos de ti'), findsOneWidget, reason: 'no avanza');
    expect(find.text('Esta cédula ya está registrada'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('un correo que ya tiene cuenta no deja pedir código', (tester) async {
    _pantallaChica(tester);
    final falso = _FalsoAuth()..emailExiste = true;
    await tester.pumpWidget(_app(falso, ThemeMode.dark));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cliente'));
    await tester.pump();
    await _continuar(tester);
    await _escribir(tester, 'Nombres', 'Ana');
    await _escribir(tester, 'Apellidos', 'Paz');
    await _escribir(tester, 'Cédula', cedulaValida);
    await _escribir(tester, 'Teléfono móvil', '0991234567');
    await _continuar(tester);
    await _escribir(tester, 'Correo electrónico', 'ana@test.com');
    expect(find.textContaining('ya tiene una cuenta'), findsOneWidget);
    await tester.tap(find.text('Enviar código'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(falso.envios, 0, reason: 'el botón está deshabilitado');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
