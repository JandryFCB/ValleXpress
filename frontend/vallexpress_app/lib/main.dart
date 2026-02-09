import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'providers/auth_provider.dart';
import 'providers/pedidos_provider.dart';

import 'config/theme.dart';
import 'config/constants.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/fcm_mobile.dart'
    if (dart.library.html) 'providers/fcm_stub_import.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<PedidosProvider>(
          create: (_) => PedidosProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'ValleXpress',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        initialRoute: AppConstants.loginRoute,
        routes: {
          AppConstants.loginRoute: (_) => const LoginScreen(),
          AppConstants.registerRoute: (_) => const RegisterScreen(),
          AppConstants.homeRoute: (_) => const HomeScreen(),
        },
      ),
    );
  }
}
