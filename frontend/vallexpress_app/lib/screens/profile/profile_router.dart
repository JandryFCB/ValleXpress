import 'package:flutter/material.dart';
import 'perfil_screen.dart';

/// Mantiene el nombre de siempre, pero ya no reparte pantallas por rol: el perfil es el mismo para todos
/// (los datos propios de cada rol se agregan en sus módulos).
class ProfileRouter extends StatelessWidget {
  const ProfileRouter({super.key});

  @override
  Widget build(BuildContext context) => const PerfilScreen();
}
