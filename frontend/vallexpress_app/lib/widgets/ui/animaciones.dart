import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../utils/formato.dart';

/// Se "hunde" un poco mientras se presiona, como un botón físico. Envuelve tarjetas y botones tocables; el
/// toque en sí lo maneja el hijo (InkWell). Si el dedo se desliza (scroll), se suelta sin hundirse.
class Pulsable extends StatefulWidget {
  const Pulsable({super.key, required this.child, this.onTap, this.escala = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double escala;

  @override
  State<Pulsable> createState() => _PulsableState();
}

class _PulsableState extends State<Pulsable> {
  bool _abajo = false;
  Offset? _inicio;

  void _fijar(bool abajo) {
    if (widget.onTap != null && _abajo != abajo) setState(() => _abajo = abajo);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _inicio = e.position;
        _fijar(true);
      },
      onPointerMove: (e) {
        if (_inicio != null && (e.position - _inicio!).distance > 12) _fijar(false);
      },
      onPointerUp: (_) => _fijar(false),
      onPointerCancel: (_) => _fijar(false),
      child: AnimatedScale(
        scale: _abajo ? widget.escala : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Aparece subiendo y haciéndose visible. Con [indice], los elementos de una lista entran uno tras otro.
class Aparecer extends StatefulWidget {
  const Aparecer({super.key, required this.child, this.indice = 0, this.desplazamiento = 24});

  final Widget child;
  final int indice;
  final double desplazamiento;

  @override
  State<Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<Aparecer> with SingleTickerProviderStateMixin {
  static const _entrada = 420;

  // Solo los primeros elementos esperan su turno: los de más abajo entran ya (no se nota y no hace esperar).
  // La espera va dentro de la misma animación (un tramo inicial quieto), sin temporizadores aparte.
  late final int _espera = 55 * widget.indice.clamp(0, 8);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: _espera + _entrada))..forward();
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Interval(_espera / (_espera + _entrada), 1, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (_, hijo) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, widget.desplazamiento * (1 - _t.value)), child: hijo),
        ),
        child: widget.child,
      );
}

/// Brillo que recorre los esqueletos de carga. Un solo brillo para toda la pantalla, así van sincronizados.
class BrilloCarga extends StatefulWidget {
  const BrilloCarga({super.key, required this.child});

  final Widget child;

  @override
  State<BrilloCarga> createState() => _BrilloCargaState();
}

class _BrilloCargaState extends State<BrilloCarga> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final base = c.borde;
    final luz = Color.lerp(c.borde, c.texto, 0.12)!;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, hijo) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = -1.5 + 3 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 1, -0.3),
            end: Alignment(x + 1, 0.3),
            colors: [base, luz, base],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(r);
        },
        child: hijo,
      ),
      child: widget.child,
    );
  }
}

/// Un bloque gris del esqueleto (va dentro de [BrilloCarga])
class Hueso extends StatelessWidget {
  const Hueso({super.key, this.ancho, this.alto = 14, this.radio = 8});

  final double? ancho;
  final double alto;
  final double radio;

  @override
  Widget build(BuildContext context) => Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(color: context.colores.borde, borderRadius: BorderRadius.circular(radio)),
      );
}

/// Esqueleto de una lista de tarjetas mientras carga: imita la forma de lo que va a aparecer
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({super.key, this.cantidad = 5, this.conImagen = true, this.altoImagen = 0, this.padding = const EdgeInsets.all(16)});

  final int cantidad;
  final bool conImagen;

  /// Si es mayor que 0, cada tarjeta lleva arriba una portada de ese alto (como las de los negocios)
  final double altoImagen;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return BrilloCarga(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: cantidad,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => Container(
          decoration: BoxDecoration(color: c.tarjeta, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.borde)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (altoImagen > 0) Hueso(alto: altoImagen, radio: 0),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (conImagen) ...[const Hueso(ancho: 52, alto: 52, radio: 14), const SizedBox(width: 14)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.55, child: const Hueso(alto: 16)),
                          const SizedBox(height: 10),
                          FractionallySizedBox(widthFactor: i.isEven ? 0.45 : 0.6, child: const Hueso(alto: 12)),
                          const SizedBox(height: 10),
                          const FractionallySizedBox(widthFactor: 0.3, child: Hueso(alto: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rebota una vez cada vez que cambia [valor] (por ejemplo, el contador del carrito al agregar algo)
class Rebote extends StatefulWidget {
  const Rebote({super.key, required this.valor, required this.child});

  final Object? valor;
  final Widget child;

  @override
  State<Rebote> createState() => _ReboteState();
}

class _ReboteState extends State<Rebote> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final Animation<double> _escala = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant Rebote viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.valor != widget.valor) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _escala, child: widget.child);
}

/// Un monto que cuenta hasta el valor nuevo cuando cambia ($8.50 → $17.00), en vez de cambiar de golpe
class DineroAnimado extends StatelessWidget {
  const DineroAnimado(this.valor, {super.key, this.estilo});

  final double valor;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: valor),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(Formato.dinero(v), style: estilo),
      );
}

/// Muestra u oculta una barra inferior deslizándola desde abajo (por ejemplo, la del carrito)
class BarraDeslizante extends StatelessWidget {
  const BarraDeslizante({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (hijo, a) => SizeTransition(
          sizeFactor: a,
          axisAlignment: -1,
          child: SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a), child: hijo),
        ),
        child: visible ? child : const SizedBox.shrink(key: ValueKey('oculta')),
      );
}

/// Pestañas de la barra inferior: conservan su estado (como IndexedStack) y la elegida aparece con un fundido
/// y un leve deslizamiento, en vez de cambiar de golpe.
class PestanasAnimadas extends StatefulWidget {
  const PestanasAnimadas({super.key, required this.indice, required this.children});

  final int indice;
  final List<Widget> children;

  @override
  State<PestanasAnimadas> createState() => _PestanasAnimadasState();
}

class _PestanasAnimadasState extends State<PestanasAnimadas> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(covariant PestanasAnimadas vieja) {
    super.didUpdateWidget(vieja);
    if (vieja.indice != widget.indice) {
      HapticFeedback.selectionClick();
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (_, hijo) => Opacity(
          opacity: 0.3 + 0.7 * _t.value,
          child: Transform.translate(offset: Offset(0, 10 * (1 - _t.value)), child: hijo),
        ),
        child: IndexedStack(index: widget.indice, children: widget.children),
      );
}

/// Lluvia de confeti sobre toda la pantalla para celebrar (pedido hecho, pedido entregado). Se quita sola.
///     Confeti.lanzar(context);
class Confeti extends StatefulWidget {
  const Confeti._({required this.alTerminar});

  final VoidCallback alTerminar;

  static void lanzar(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entrada;
    entrada = OverlayEntry(builder: (_) => IgnorePointer(child: Confeti._(alTerminar: () => entrada.remove())));
    overlay.insert(entrada);
    HapticFeedback.heavyImpact();
  }

  @override
  State<Confeti> createState() => _ConfetiState();
}

class _ConfetiState extends State<Confeti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final _azar = math.Random();
  late final List<_Papelito> _papelitos;

  static const _colores = [AppTheme.primaryColor, AppTheme.accentColor, AppTheme.successColor, AppTheme.infoColor, Color(0xFFFF6B8B), Colors.white];

  @override
  void initState() {
    super.initState();
    _papelitos = List.generate(90, (_) {
      final angulo = -math.pi / 2 + (_azar.nextDouble() - 0.5) * 1.6;      // hacia arriba, abierto en abanico
      final fuerza = 0.9 + _azar.nextDouble() * 0.9;
      return _Papelito(
        x: 0.5 + (_azar.nextDouble() - 0.5) * 0.3,
        vx: math.cos(angulo) * fuerza * 0.55,
        vy: math.sin(angulo) * fuerza * 1.25,
        giro: (_azar.nextDouble() - 0.5) * 18,
        color: _colores[_azar.nextInt(_colores.length)],
        ancho: 6 + _azar.nextDouble() * 6,
        redondo: _azar.nextBool(),
      );
    });
    _c.forward().whenComplete(widget.alTerminar);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(size: Size.infinite, painter: _PintorConfeti(_papelitos, _c.value)),
      );
}

class _Papelito {
  const _Papelito({required this.x, required this.vx, required this.vy, required this.giro, required this.color, required this.ancho, required this.redondo});

  final double x, vx, vy, giro, ancho;
  final Color color;
  final bool redondo;
}

class _PintorConfeti extends CustomPainter {
  _PintorConfeti(this.papelitos, this.t);

  final List<_Papelito> papelitos;
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    final pintura = Paint();
    final opacidad = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    for (final p in papelitos) {
      // Sale desde abajo al centro, sube y cae con gravedad
      final x = (p.x + p.vx * t) * s.width;
      final y = s.height * (1.02 + p.vy * t + 1.6 * t * t);
      pintura.color = p.color.withValues(alpha: opacidad.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.giro * t);
      if (p.redondo) {
        canvas.drawCircle(Offset.zero, p.ancho / 2.4, pintura);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.ancho, height: p.ancho * 0.45), const Radius.circular(1.5)), pintura);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PintorConfeti viejo) => viejo.t != t;
}

/// Ícono grande dentro de un círculo que "late" mientras [activo] (algo está en marcha) y aparece con un salto
/// elástico cada vez que cambia (por ejemplo, el estado del pedido).
class IconoLatiendo extends StatefulWidget {
  const IconoLatiendo({super.key, required this.icono, required this.color, this.activo = true, this.tamano = 84});

  final IconData icono;
  final Color color;
  final bool activo;
  final double tamano;

  @override
  State<IconoLatiendo> createState() => _IconoLatiendoState();
}

class _IconoLatiendoState extends State<IconoLatiendo> with SingleTickerProviderStateMixin {
  late final AnimationController _latido = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.activo) _latido.repeat();
  }

  @override
  void didUpdateWidget(covariant IconoLatiendo viejo) {
    super.didUpdateWidget(viejo);
    if (widget.activo && !_latido.isAnimating) _latido.repeat();
    if (!widget.activo && _latido.isAnimating) _latido.stop();
  }

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tamano;
    return SizedBox(
      width: t * 1.5,
      height: t * 1.5,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.activo)
            AnimatedBuilder(
              animation: _latido,
              builder: (_, _) => Container(
                width: t + t * 0.5 * _latido.value,
                height: t + t * 0.5 * _latido.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.22 * (1 - _latido.value))),
              ),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 550),
            switchInCurve: Curves.elasticOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (hijo, a) => ScaleTransition(scale: a, child: hijo),
            child: Container(
              key: ValueKey(widget.icono),
              width: t,
              height: t,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.16)),
              child: Icon(widget.icono, color: widget.color, size: t * 0.48),
            ),
          ),
        ],
      ),
    );
  }
}
