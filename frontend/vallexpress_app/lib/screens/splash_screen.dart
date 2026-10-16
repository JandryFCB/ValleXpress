import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Pantalla de arranque: se muestra mientras la app revisa si hay una sesión guardada (normalmente < 1 segundo;
/// un poco más si el token de acceso venció y hay que renovarlo).
/// Continúa la pantalla de arranque de Android (mismo azul noche y el logo del mismo tamaño en el mismo lugar),
/// así no se nota el cambio: luego el logo late, aparece el nombre y unos puntos de carga.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _entrada = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final AnimationController _bucle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _entrada.dispose();
    _bucle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final texto = CurvedAnimation(parent: _entrada, curve: const Interval(0.35, 1, curve: Curves.easeOutCubic));
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: [AppTheme.backgroundGradientEnd, AppTheme.backgroundColor], radius: 0.9),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Logo en el centro exacto (como el de Android), latiendo suave con un halo verde
            AnimatedBuilder(
              animation: _bucle,
              builder: (_, hijo) {
                final t = math.sin(_bucle.value * 2 * math.pi);
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.25 + 0.15 * t), blurRadius: 40 + 16 * t, spreadRadius: 2)],
                  ),
                  child: Transform.scale(scale: 1 + 0.025 * t, child: hijo),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Image.asset('assets/images/logo.png', width: 136, height: 136, fit: BoxFit.cover),
              ),
            ),
            // Debajo: el lema y los puntos de carga, que entran después
            Positioned(
              left: 24,
              right: 24,
              top: MediaQuery.sizeOf(context).height / 2 + 100,
              child: FadeTransition(
                opacity: texto,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(texto),
                  child: Column(
                    children: [
                      Text('Lo mejor del valle, a tu puerta',
                          textAlign: TextAlign.center, style: tema.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 22),
                      AnimatedBuilder(
                        animation: _bucle,
                        builder: (_, _) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Builder(builder: (_) {
                                // Cada punto sube y se ilumina un poco después del anterior
                                final fase = (_bucle.value - i * 0.18) % 1;
                                final alto = math.max(0.0, math.sin(fase * math.pi));
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 5),
                                  width: 9,
                                  height: 9,
                                  transform: Matrix4.translationValues(0, -8 * alto, 0),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.lerp(AppTheme.primaryColor.withValues(alpha: 0.45), AppTheme.accentColor, alto),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
