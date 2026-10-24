import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'escritorio.dart';

/// Página de computador: título grande con subtítulo y acciones a la derecha, y el contenido debajo con un ancho
/// cómodo. [child] se desplaza solo (si es una lista con su propio desplazamiento, usar [desplazable] = false).
class PaginaEscritorio extends StatelessWidget {
  const PaginaEscritorio({
    super.key,
    required this.titulo,
    required this.child,
    this.subtitulo,
    this.acciones = const [],
    this.icono,
    this.desplazable = true,
    this.ancho = double.infinity,
    this.debajoDelTitulo,
    this.conAtras = false,
    this.anchoTitulo,
  });

  final String titulo;
  final String? subtitulo;
  final IconData? icono;
  final List<Widget> acciones;
  final Widget child;
  final bool desplazable;
  final double ancho;

  /// Algo fijo entre el título y el contenido (pestañas, filtros)
  final Widget? debajoDelTitulo;

  /// Flecha para volver (páginas abiertas encima de otra)
  final bool conAtras;

  /// Ancho máximo del título y subtítulo (el subtítulo baja de línea en vez de pasar sobre una columna)
  final double? anchoTitulo;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    Widget limitado(Widget w, {EdgeInsets relleno = const EdgeInsets.symmetric(horizontal: margenWeb)}) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: Padding(padding: relleno, child: w)),
        );

    final cabecera = limitado(
      Row(
        children: [
          if (conAtras) ...[
            IconButton.filledTonal(tooltip: 'Volver', onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 16),
          ],
          if (icono != null) ...[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
              child: Icon(icono, color: c.primario, size: 28),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: anchoTitulo ?? double.infinity),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: tema.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                    if (subtitulo != null) ...[const SizedBox(height: 2), Text(subtitulo!, style: tema.bodyLarge?.copyWith(color: c.textoSuave))],
                  ],
                ),
              ),
            ),
          ),
          ...acciones,
        ],
      ),
      relleno: const EdgeInsets.fromLTRB(margenWeb, 28, margenWeb, 20),
    );

    return Scaffold(
      backgroundColor: c.fondo,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cabecera,
          if (debajoDelTitulo != null) limitado(debajoDelTitulo!),
          Expanded(
            child: desplazable
                ? SingleChildScrollView(padding: const EdgeInsets.only(bottom: 40), child: limitado(child))
                : limitado(child, relleno: const EdgeInsets.fromLTRB(margenWeb, 0, margenWeb, 0)),
          ),
        ],
      ),
    );
  }
}

/// Reparte bloques en dos columnas que se llenan alternando (izquierda, derecha, izquierda...); en una pantalla
/// angosta, una sola columna
class DosColumnas extends StatelessWidget {
  const DosColumnas({super.key, required this.hijos, this.espacio = 20}) : izquierda = null, derecha = null;

  /// Columnas armadas a mano (para equilibrar el alto); en pantallas angostas va primero la izquierda
  const DosColumnas.fijas({super.key, required List<Widget> this.izquierda, required List<Widget> this.derecha, this.espacio = 20})
      : hijos = const [];

  final List<Widget> hijos;
  final List<Widget>? izquierda;
  final List<Widget>? derecha;
  final double espacio;

  Widget _pila(List<Widget> lista) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, h) in lista.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : espacio), child: h),
      ]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, medidas) {
      if (izquierda != null && derecha != null) {
        if (medidas.maxWidth < 640) return _pila([...izquierda!, ...derecha!]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _pila(izquierda!)),
          SizedBox(width: espacio),
          Expanded(child: _pila(derecha!)),
        ]);
      }
      if (medidas.maxWidth < 640) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, h) in hijos.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : espacio), child: h),
        ]);
      }
      Widget columna(int resto) => Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = resto; i < hijos.length; i += 2) Padding(padding: EdgeInsets.only(top: i < 2 ? 0 : espacio), child: hijos[i]),
            ]),
          );
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [columna(0), SizedBox(width: espacio), columna(1)]);
    });
  }
}
