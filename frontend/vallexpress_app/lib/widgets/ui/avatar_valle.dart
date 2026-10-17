import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Círculo con las iniciales de la persona (o su foto si hay una URL).
class AvatarValle extends StatelessWidget {
  const AvatarValle({super.key, required this.nombre, this.apellido, this.fotoUrl, this.tamano = 56, this.color});

  final String nombre;
  final String? apellido;
  final String? fotoUrl;
  final double tamano;
  final Color? color;

  String get _iniciales {
    String primera(String? t) => (t ?? '').trim().isEmpty ? '' : t!.trim()[0].toUpperCase();
    final i = '${primera(nombre)}${primera(apellido)}';
    return i.isEmpty ? '?' : i;
  }

  @override
  Widget build(BuildContext context) {
    final tinte = color ?? context.colores.primario;
    final foto = (fotoUrl != null && fotoUrl!.isNotEmpty) ? fotoUrl : null;
    // Material propio: durante la animación Hero (lista -> detalle), o si se minimiza la app a mitad de ella, el
    // avatar se dibuja fuera de la pantalla y las iniciales salían con el subrayado amarillo de "texto sin estilo".
    return Material(
      type: MaterialType.transparency,
      child: Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [tinte, tinte.withValues(alpha: 0.65)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        image: foto == null ? null : DecorationImage(image: NetworkImage(foto), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: foto == null
          ? Text(_iniciales, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: tamano * 0.38, decoration: TextDecoration.none))
          : null,
      ),
    );
  }
}
