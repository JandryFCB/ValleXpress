import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../web/escritorio.dart';

/// Fondo estándar de las pantallas: degradado del tema (claro u oscuro) y zona segura. Todas las pantallas nuevas
/// se construyen sobre esto para verse iguales.
///
///     FondoValle(titulo: 'Mis direcciones', child: ...)
class FondoValle extends StatelessWidget {
  const FondoValle({
    super.key,
    required this.child,
    this.titulo,
    this.acciones,
    this.appBar,
    this.botonFlotante,
    this.barraInferior,
    this.conFlechaAtras = true,
    this.zonaSegura = true,
    this.resizeToAvoidBottomInset = true,
    this.anchoCompleto = false,
    this.anchoEscritorio = 1200,
  });

  final Widget child;

  /// Título simple en la barra superior (si se necesita algo más complejo, usa [appBar])
  final String? titulo;
  final List<Widget>? acciones;
  final PreferredSizeWidget? appBar;
  final Widget? botonFlotante;
  final Widget? barraInferior;
  final bool conFlechaAtras;
  final bool zonaSegura;
  final bool resizeToAvoidBottomInset;

  /// En el computador la pantalla se centra con un ancho cómodo; true = usa todo el ancho (mapas, tableros)
  final bool anchoCompleto;

  /// Ancho máximo en el computador (los tableros usan más)
  final double anchoEscritorio;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final barra = appBar ??
        (titulo == null
            ? null
            : AppBar(
                title: Text(titulo!),
                actions: acciones,
                automaticallyImplyLeading: conFlechaAtras,
              ));

    final pantalla = Scaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: barra,
      floatingActionButton: botonFlotante,
      bottomNavigationBar: barraInferior,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: c.degradadoFondo),
        child: zonaSegura ? SafeArea(top: barra == null, child: child) : child,
      ),
    );
    if (!esEscritorio(context)) return pantalla;
    // Computador: títulos grandes en negrita y más aire arriba, como una página web (vale para todas las pantallas)
    final tema = Theme.of(context);
    return ColoredBox(
      color: c.fondo,
      child: Theme(
        data: tema.copyWith(
          appBarTheme: tema.appBarTheme.copyWith(
            toolbarHeight: 88,
            titleSpacing: 24,
            titleTextStyle: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.texto),
          ),
        ),
        child: anchoCompleto ? pantalla : AnchoMaximo(ancho: anchoEscritorio, child: pantalla),
      ),
    );
  }
}
