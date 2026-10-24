import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/negocio.dart';
import '../providers/auth_provider.dart';
import '../utils/formato.dart';
import '../widgets/ui/ui.dart';

// Piezas del inicio del cliente en el computador (la lógica de carga está en NegociosScreen).

/// Colores suaves de cada categoría (estilo "Fresco"): (fondo pastel, color del ícono y del texto encima)
(Color, Color) colorCategoria(String? codigo) => switch (codigo) {
      '001' => (const Color(0xFFFFF1D1), const Color(0xFF8A5A00)), // comida
      '002' => (const Color(0xFFE9E4FB), const Color(0xFF4F3AA0)), // bebidas
      '003' => (const Color(0xFFFCE7F3), const Color(0xFF9D2B6B)), // postres
      '004' => (const Color(0xFFF3E8DC), const Color(0xFF7A4B1F)), // panadería
      '005' => (const Color(0xFFDDF1E3), const Color(0xFF187A3C)), // supermercado
      '006' => (const Color(0xFFDDEFFC), const Color(0xFF145A8C)), // farmacia
      '007' => (const Color(0xFFFCE3E0), const Color(0xFF9A3328)), // mascotas
      null => (const Color(0xFFE6ECE8), const Color(0xFF15201A)), // todos
      _ => (const Color(0xFFEEF0EF), const Color(0xFF4A5650)),
    };

/// Igual que [colorCategoria] pero según el modo: en oscuro el pastel se vuelve un tono apagado y el ícono toma el
/// color claro (el pastel encendido deslumbraba sobre el fondo oscuro)
(Color, Color) coloresCategoria(BuildContext context, String? codigo) {
  final (fondo, tinta) = colorCategoria(codigo);
  if (Theme.of(context).brightness != Brightness.dark) return (fondo, tinta);
  return (Color.alphaBlend(fondo.withValues(alpha: 0.14), context.colores.tarjetaElevada), fondo);
}

/// Margen lateral del inicio: todo el ancho de la pantalla con el mismo aire que la barra de arriba
double margenEscritorio(BuildContext context) => margenWeb;

/// Bienvenida verde con el buscador
class BienvenidaEscritorio extends StatelessWidget {
  const BienvenidaEscritorio({super.key, required this.buscador});

  final Widget buscador;

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final nombre = (context.select<AuthProvider, String?>((a) => a.usuario?['nombre']?.toString()) ?? '').split(' ').first;
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 40, 40, 40),
      decoration: BoxDecoration(color: const Color(0xFF187A3C), borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '${_saludo()}${nombre.isEmpty ? '' : ', $nombre'}',
                    style: tema.labelLarge?.copyWith(color: const Color(0xFF15201A), fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '¿Qué te llevamos hoy?',
                  style: tema.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.05),
                ),
                const SizedBox(height: 10),
                Text(
                  'Comida, tiendas, farmacias, mascotas y más. Pide en minutos y sigue tu pedido en vivo.',
                  style: tema.titleMedium?.copyWith(color: const Color(0xFFD6F0DE), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: buscador),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 1100) ...[
            const SizedBox(width: 40),
            Container(
              width: 300,
              height: 260,
              decoration: BoxDecoration(color: const Color(0xFF2B9B55), borderRadius: BorderRadius.circular(24)),
              alignment: Alignment.center,
              child: Flotar(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: Image.asset('assets/images/logo.png', width: 180, height: 180, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ficha blanca de una categoría con su ícono sobre un color suave (seleccionable)
class FichaCategoria extends StatefulWidget {
  const FichaCategoria({super.key, required this.codigo, required this.texto, required this.icono, required this.seleccionada, required this.onTap});

  final String? codigo;
  final String texto;
  final IconData icono;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  State<FichaCategoria> createState() => _FichaCategoriaState();
}

class _FichaCategoriaState extends State<FichaCategoria> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final (fondo, tinta) = coloresCategoria(context, widget.codigo);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, _encima ? -3 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          decoration: BoxDecoration(
            color: c.tarjeta,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.seleccionada ? c.primario : c.borde, width: widget.seleccionada ? 2 : 1),
            boxShadow: [if (_encima) BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(18)),
                    child: Icon(widget.icono, color: tinta, size: 28),
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(widget.texto, maxLines: 1, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ],
              ),
              if (widget.seleccionada) Positioned(top: 0, right: 0, child: Icon(Icons.check_circle_rounded, color: c.primario, size: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca de un negocio: foto arriba con "Abierto"/"Cerrado", y debajo nombre, categoría, tiempo y envío
class TarjetaNegocioEscritorio extends StatefulWidget {
  const TarjetaNegocioEscritorio({super.key, required this.negocio, required this.onTap});

  final Negocio negocio;
  final VoidCallback onTap;

  @override
  State<TarjetaNegocioEscritorio> createState() => _TarjetaNegocioEscritorioState();
}

class _TarjetaNegocioEscritorioState extends State<TarjetaNegocioEscritorio> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final n = widget.negocio;
    final (fondo, tinta) = coloresCategoria(context, n.categoria.codigo);
    final envio = n.costoEnvio == 0 ? 'Envío gratis' : 'Envío ${n.envioEstimado ? '' : 'desde '}${Formato.dinero(n.costoEnvio)}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, _encima ? -4 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.tarjeta,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: const Color(0xFF102818).withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1)),
              BoxShadow(color: const Color(0xFF102818).withValues(alpha: _encima ? 0.14 : 0.06), blurRadius: _encima ? 28 : 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'portada-negocio-${n.id}',
                      child: n.portada != null
                          ? ImagenRed(url: n.portada, radio: 0)
                          : Container(color: fondo, child: Icon(n.categoria.icono, size: 56, color: tinta.withValues(alpha: 0.7))),
                    ),
                    if (!n.abiertoAhora) Container(color: Colors.black.withValues(alpha: 0.30)),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _Pastilla(
                        n.abiertoAhora ? 'Abierto' : 'Cerrado',
                        fondo: n.abiertoAhora ? Colors.white : const Color(0xFF15201A),
                        tinta: n.abiertoAhora ? const Color(0xFF187A3C) : Colors.white,
                      ),
                    ),
                    if (n.logo != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white, width: 2)),
                          child: ImagenRed(url: n.logo, ancho: 44, alto: 44, radio: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(n.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (n.numeroCalificaciones > 0) ...[
                          const Icon(Icons.star_rounded, size: 18, color: AppTheme.accentColor),
                          Text(' ${n.calificacion.toStringAsFixed(1)}', style: tema.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(n.categoria.descripcion, style: tema.bodyMedium?.copyWith(color: c.textoSuave), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      '${n.tiempoPreparacion} min · $envio',
                      style: tema.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: c.texto),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _Pastilla extends StatelessWidget {
  const _Pastilla(this.texto, {required this.fondo, required this.tinta});

  final String texto;
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(99)),
        child: Text(texto, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: tinta, fontWeight: FontWeight.w800)),
      );
}
