import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Pregunta si se usa la cámara o la galería, deja elegir una foto y la devuelve en base64 (como la espera el
/// servidor, que luego la optimiza). Devuelve null si el usuario cancela.
Future<String?> elegirImagenBase64(BuildContext context, {String titulo = 'Elegir imagen'}) async {
  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(titulo, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar una foto'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (origen == null) return null;
  // Se reduce en el teléfono antes de enviarla (menos datos móviles); el servidor la optimiza otra vez
  final foto = await ImagePicker().pickImage(source: origen, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
  if (foto == null) return null;
  return base64Encode(await foto.readAsBytes());
}
