import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/ui/ui.dart';

/// Hoja para escribir el motivo de una decisión del administrador (rechazar, suspender, bloquear, cancelar).
/// Ofrece motivos frecuentes de un toque y deja escribir uno propio. Devuelve null si se cierra sin confirmar.
Future<String?> pedirMotivo(
  BuildContext context, {
  required String titulo,
  required String explicacion,
  required String textoBoton,
  List<String> sugerencias = const [],
  int minimo = 5,
}) {
  return mostrarHoja<String>(context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HojaMotivo(titulo: titulo, explicacion: explicacion, textoBoton: textoBoton, sugerencias: sugerencias, minimo: minimo),
  );
}

class _HojaMotivo extends StatefulWidget {
  const _HojaMotivo({required this.titulo, required this.explicacion, required this.textoBoton, required this.sugerencias, required this.minimo});

  final String titulo;
  final String explicacion;
  final String textoBoton;
  final List<String> sugerencias;
  final int minimo;

  @override
  State<_HojaMotivo> createState() => _HojaMotivoState();
}

class _HojaMotivoState extends State<_HojaMotivo> {
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  bool get _valido => _texto.text.trim().length >= widget.minimo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.titulo, style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.explicacion, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            if (widget.sugerencias.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.sugerencias)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => setState(() => _texto.text = s),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _texto,
              maxLength: 250,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Escribe el motivo', prefixIcon: Icon(Icons.edit_note_rounded)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            BotonValle(
              texto: widget.textoBoton,
              tipo: TipoBoton.peligro,
              onPressed: _valido ? () => Navigator.pop(context, _texto.text.trim()) : null,
            ),
          ],
        ),
      ),
    );
  }
}
