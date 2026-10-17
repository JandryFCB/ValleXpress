import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/legal/documento_legal_screen.dart';

const _clave = 'aviso_ubicacion_repartidor_v1';

/// Aviso destacado antes de pedir la ubicación al repartidor (Google Play lo exige cuando la ubicación se usa con la
/// app minimizada o la pantalla apagada). Se muestra una sola vez por celular; devuelve true si el repartidor
/// acepta (o ya lo había aceptado antes).
Future<bool> confirmarAvisoUbicacion(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_clave) == true) return true;
  if (!context.mounted) return false;
  final tema = Theme.of(context).textTheme;
  final acepta = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.my_location_rounded, size: 40),
      title: const Text('Uso de tu ubicación'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ValleXpress recopila tu ubicación precisa para asignarte pedidos cercanos y para que el cliente y el negocio vean '
              'en el mapa dónde va su entrega, incluso cuando la app está cerrada o no se está usando (minimizada o con la '
              'pantalla apagada).',
            ),
            const SizedBox(height: 10),
            const Text('Solo ocurre mientras estás "En línea" o llevas un pedido, y tu celular muestra una notificación fija mientras tanto. Al desconectarte, deja de enviarse.'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => abrirDocumentoLegal(ctx, 'privacidad'),
              child: Text('Ver la Política de privacidad', style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, gracias')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entendido, continuar')),
      ],
    ),
  );
  if (acepta == true) await prefs.setBool(_clave, true);
  return acepta == true;
}
