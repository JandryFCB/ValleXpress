import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'escritorio.dart';

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
    if (anchoCompleto || !esEscritorio(context)) return pantalla;
    return ColoredBox(color: c.fondo, child: AnchoMaximo(child: pantalla));
  }
}
