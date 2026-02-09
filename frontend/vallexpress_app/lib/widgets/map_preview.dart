import 'package:flutter/material.dart';

class MapPreview extends StatelessWidget {
  final VoidCallback onTap;

  const MapPreview({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF0F2F3A),
          border: Border.all(color: Colors.white12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Fondo: intenta cargar imagen, si falla usa gradiente (sin rojos ni crasheos)
            Positioned.fill(
              child: Image.asset(
                'assets/images/map_bg.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0B1F26), Color(0xFF0F3A4A)],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Oscurecer un poquito para que se lea el texto
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),

            // Icono repartidor (centro)
            const Center(
              child: Icon(
                Icons.delivery_dining,
                size: 44,
                color: Color(0xFFFDB827),
              ),
            ),

            // Etiqueta inferior
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ver rastreo en tiempo real',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Color(0xFFFDB827),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
