import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/validadores.dart';

/// Barra de 4 tramos que muestra qué tan fuerte es una contraseña, con su etiqueta (Débil, Aceptable, Buena, Fuerte).
class MedidorClave extends StatelessWidget {
  const MedidorClave({super.key, required this.clave});

  final String clave;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final fuerza = Validadores.fuerzaClave(clave);
    final color = [c.borde, AppTheme.errorColor, AppTheme.warningColor, AppTheme.infoColor, AppTheme.successColor][fuerza];
    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 5,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                  decoration: BoxDecoration(color: i < fuerza ? color : c.borde, borderRadius: BorderRadius.circular(4)),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 76,
          child: Text(
            Validadores.textoFuerza(fuerza),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
