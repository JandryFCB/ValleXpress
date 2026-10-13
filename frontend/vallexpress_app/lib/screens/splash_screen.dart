import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Pantalla de arranque: se muestra mientras la app revisa si hay una sesión guardada (normalmente < 1 segundo;
/// un poco más si el token de acceso venció y hay que renovarlo).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.degradadoFondo),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (context, escala, hijo) => Opacity(
                  opacity: escala.clamp(0.0, 1.0),
                  child: Transform.scale(scale: escala, child: hijo),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset('assets/images/logo.png', width: 140, height: 140),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3, color: c.primario),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
