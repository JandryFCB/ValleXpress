import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class TermsAndConditionsView extends StatelessWidget {
  final String userRole;
  const TermsAndConditionsView({super.key, required this.userRole});

  String _pdfPath() {
    switch (userRole.toLowerCase()) {
      case 'cliente':
        return 'assets/documents/terminos_cliente.pdf';
      case 'vendedor':
        return 'assets/documents/terminos_vendedor.pdf';
      case 'repartidor':
        return 'assets/documents/terminos_repartidor.pdf';
      default:
        return 'assets/documents/terminos_cliente.pdf';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SfPdfViewer.asset(_pdfPath());
  }
}
