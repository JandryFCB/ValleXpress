import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/negocio.dart';
import '../providers/auth_provider.dart';
import '../utils/formato.dart';
import '../widgets/ui/ui.dart';

// Piezas del inicio del cliente en el computador (la lógica de carga está en NegociosScreen).

/// Color vivo de cada categoría (las fichas de colores del inicio). Texto encima: azul marino.
Color colorCategoria(String? codigo) => switch (codigo) {
      '001' => const Color(0xFFFF7A59), // comida
      '002' => const Color(0xFF2F9BE0), // bebidas
      '003' => const Color(0xFFB58AF0), // heladería
      '004' => const Color(0xFFF6B92B), // panadería
      '005' => const Color(0xFF35B35A), // víveres
      '006' => const Color(0xFF3CC0B8), // farmacia
      '007' => const Color(0xFFF28FB1), // mascotas
      null => const Color(0xFF0B1A2B), // todos
      _ => const Color(0xFFC9D3CE),
    };

const _marino = Color(0xFF0B1A2B);

/// Margen lateral: el contenido queda centrado en 1280 px con 32 de aire (alineado con la barra de arriba)
double margenEscritorio(BuildContext context) {
  final ancho = MediaQuery.sizeOf(context).width;
  return (ancho > 1280 ? (ancho - 1280) / 2 : 0) + 32;
}

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

/// Ficha de color de una categoría (seleccionable)
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
    final fondo = colorCategoria(widget.codigo);
    final tinta = fondo == _marino ? Colors.white : _marino;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, _encima ? -4 : 0, 0),
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: widget.seleccionada ? _marino : Colors.transparent, width: 3),
            boxShadow: [if (_encima || widget.seleccionada) BoxShadow(color: fondo.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(widget.icono, color: tinta, size: 28),
                  const Spacer(),
                  if (widget.seleccionada) Icon(Icons.check_circle_rounded, color: tinta, size: 22),
                ],
              ),
              // Nombres largos ("Supermercado") se achican en vez de cortarse
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(widget.texto, maxLines: 1, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: tinta, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta grande de un negocio: foto con "Abierto"/"Cerrado" y el tiempo, y debajo nombre, categoría y envío
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
    final color = colorCategoria(n.categoria.codigo);
    final envio = n.costoEnvio == 0 ? 'Envío gratis' : 'Envío ${n.envioEstimado ? '' : 'desde '}${Formato.dinero(n.costoEnvio)}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedScale(
                scale: _encima ? 1.02 : 1,
                duration: const Duration(milliseconds: 180),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'portada-negocio-${n.id}',
                        child: n.portada != null
                            ? ImagenRed(url: n.portada, radio: 0)
                            : Container(
                                color: Color.alphaBlend(color.withValues(alpha: 0.35), Colors.white),
                                child: Icon(n.categoria.icono, size: 64, color: _marino.withValues(alpha: 0.55)),
                              ),
                      ),
                      if (!n.abiertoAhora) Container(color: Colors.black.withValues(alpha: 0.35)),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _Pastilla(
                          n.abiertoAhora ? 'Abierto' : 'Cerrado',
                          fondo: n.abiertoAhora ? const Color(0xFF35B35A) : _marino,
                          tinta: n.abiertoAhora ? _marino : Colors.white,
                        ),
                      ),
                      Positioned(left: 12, bottom: 12, child: _Pastilla('${n.tiempoPreparacion} min', fondo: Colors.white, tinta: _marino)),
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
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(n.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (n.numeroCalificaciones > 0) ...[
                    const Icon(Icons.star_rounded, size: 18, color: AppTheme.accentColor),
                    Text(' ${n.calificacion.toStringAsFixed(1)}', style: tema.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
              child: Text(
                '${n.categoria.descripcion} · $envio',
                style: tema.bodyMedium?.copyWith(color: c.textoSuave),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
