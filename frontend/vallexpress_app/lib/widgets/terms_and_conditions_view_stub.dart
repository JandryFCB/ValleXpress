import 'package:flutter/material.dart';

class TermsAndConditionsView extends StatelessWidget {
  final String userRole;
  const TermsAndConditionsView({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('PDF no soportado en esta plataforma'));
  }
}
