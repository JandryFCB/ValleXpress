import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'providers/auth_provider.dart';
import 'providers/carrito_provider.dart';
import 'providers/tema_provider.dart';

import 'config/theme.dart';
import 'config/constants.dart';
import 'config/navegacion.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/inicio/inicio_screen.dart';
import 'screens/splash_screen.dart';
import 'services/version_app.dart';
import 'services/fcm_mobile.dart'
    if (dart.library.html) 'providers/fcm_stub_import.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Solo vertical: las pantallas están diseñadas para el celular de pie (girarlo descuadraba el diseño).
  // En Android también lo fija el manifiesto (screenOrientation) para que no gire ni durante el arranque.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Inicializar FCM (Firebase Cloud Messaging)
  if (!kIsWeb) {
    try {
      await FcmService.initialize();
      debugPrint('✅ FCM inicializado correctamente');
    } catch (e) {
      debugPrint('❌ Error inicializando FCM: $e');
    }
  }

  runApp(const MyApp());
  // Aviso de versión nueva (la app se reparte como APK): se revisa poco después de abrir
  Future.delayed(const Duration(seconds: 3), VersionApp.revisar);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<TemaProvider>(create: (_) => TemaProvider()),
        ChangeNotifierProvider<CarritoProvider>(create: (_) => CarritoProvider()),
      ],
      child: Consumer<TemaProvider>(
        builder: (context, tema, _) => MaterialApp(
        title: 'ValleXpress',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: tema.modo,
        home: const _PuertaDeSesion(),
        routes: {
          AppConstants.loginRoute: (_) => const LoginScreen(),
          AppConstants.registerRoute: (_) => const RegisterScreen(),
          AppConstants.homeRoute: (_) => const InicioScreen(),
        },
        ),
      ),
    );
  }
}

/// Decide la primera pantalla UNA sola vez: si hay una sesión guardada, directo al inicio (sin pedir la clave);
/// si no, al login. Mientras se revisa, muestra la pantalla de arranque.
class _PuertaDeSesion extends StatefulWidget {
  const _PuertaDeSesion();

  @override
  State<_PuertaDeSesion> createState() => _PuertaDeSesionState();
}

class _PuertaDeSesionState extends State<_PuertaDeSesion> {
  Widget? _destino;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoring) return const SplashScreen();
    // Después de decidir no se vuelve a reaccionar: el login y el cierre de sesión navegan por su cuenta
    return _destino ??= auth.isAuthenticated ? const InicioScreen() : const LoginScreen();
  }
}
