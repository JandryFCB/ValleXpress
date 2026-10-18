import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/documento_repartidor.dart';
import '../services/api_error.dart';
import '../services/pedidos_service.dart';
import '../utils/formato.dart';
import '../utils/imagen.dart';
import 'ui/ui.dart';

IconData _iconoDe(String tipo) => switch (tipo) {
      'selfie' => Icons.face_retouching_natural_rounded,
      'licencia' => Icons.badge_rounded,
      'matricula' => Icons.description_rounded,
      _ => Icons.credit_card_rounded,
    };

/// Abre la foto de un documento en grande (se puede ampliar con los dedos)
void verDocumento(BuildContext context, DocumentoRepartidor d) {
  if (d.url == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(d.titulo)),
        body: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(d.url!, fit: BoxFit.contain))),
      ),
    ),
  );
}

/// Lista de documentos del repartidor: miniatura, estado y (para el repartidor) el botón para subir o cambiar
class ListaDocumentos extends StatelessWidget {
  const ListaDocumentos({super.key, required this.docs, this.onSubir, this.subiendo});

  final DocumentosRepartidor docs;
  final Future<void> Function(DocumentoRepartidor)? onSubir;
  final String? subiendo; // tipo que se está subiendo

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return Column(
      children: [
        for (final (i, d) in docs.documentos.indexed) ...[
          if (i > 0) Divider(height: 1, color: c.borde),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => verDocumento(context, d),
                  child: d.subido
                      ? ImagenRed(url: d.miniatura ?? d.url, ancho: 64, alto: 48, radio: 8)
                      : Container(
                          width: 64,
                          height: 48,
                          decoration: BoxDecoration(color: c.borde.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                          child: Icon(_iconoDe(d.tipo), color: c.textoSuave),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        d.subido ? 'Subido ${d.fecha == null ? '' : Formato.fechaRelativa(d.fecha!).toLowerCase()}' : d.ayuda,
                        style: tema.bodySmall?.copyWith(color: d.subido ? AppTheme.successColor : c.textoSuave),
                      ),
                    ],
                  ),
                ),
                if (onSubir != null)
                  subiendo == d.tipo
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : TextButton(onPressed: subiendo == null ? () => onSubir!(d) : null, child: Text(d.subido ? 'Cambiar' : 'Subir'))
                else
                  Icon(d.subido ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: d.subido ? AppTheme.successColor : AppTheme.warningColor),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Tarjeta "Tus documentos" del repartidor: los carga, los muestra y deja subirlos con la cámara o la galería
class MisDocumentos extends StatefulWidget {
  const MisDocumentos({super.key, this.alCambiar});

  final VoidCallback? alCambiar;

  @override
  State<MisDocumentos> createState() => _MisDocumentosState();
}

class _MisDocumentosState extends State<MisDocumentos> {
  DocumentosRepartidor? _docs;
  String? _error;
  String? _subiendo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final d = await PedidosService.misDocumentos();
      if (mounted) setState(() => (_docs = d, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _subir(DocumentoRepartidor d) async {
    final imagen = await elegirImagenBase64(context, titulo: d.titulo);
    if (imagen == null || !mounted) return;
    setState(() => _subiendo = d.tipo);
    try {
      final antes = _docs?.completos ?? false;
      final nuevos = await PedidosService.subirDocumento(d.tipo, imagen);
      if (!mounted) return;
      setState(() => _docs = nuevos);
      HapticFeedback.lightImpact();
      mostrarExito(context, !antes && nuevos.completos ? '¡Listo! Tus documentos están completos' : '${d.titulo}: guardado');
      widget.alCambiar?.call();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _subiendo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final docs = _docs;
    final color = docs == null ? context.colores.primario : (docs.completos ? AppTheme.successColor : AppTheme.warningColor);
    return TarjetaValle(
      colorBorde: docs != null && !docs.completos ? AppTheme.warningColor.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_user_rounded, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text('Tus documentos', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (docs != null)
              InsigniaValle(
                docs.completos ? 'Completos' : 'Faltan ${docs.faltan}',
                color: color,
                icono: docs.completos ? Icons.check_rounded : Icons.upload_rounded,
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Para aprobar tu cuenta verificamos tu identidad y tu vehículo. Solo los ve el equipo de ValleXpress.',
            style: tema.bodySmall?.copyWith(color: context.colores.textoSuave),
          ),
          const SizedBox(height: 6),
          if (docs != null)
            ListaDocumentos(docs: docs, onSubir: _subir, subiendo: _subiendo)
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(child: Text(_error!, style: tema.bodySmall?.copyWith(color: AppTheme.errorColor))),
                TextButton(onPressed: _cargar, child: const Text('Reintentar')),
              ]),
            )
          else
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

/// Pantalla "Mis documentos" (desde el perfil del repartidor)
class MisDocumentosScreen extends StatelessWidget {
  const MisDocumentosScreen({super.key});

  @override
  Widget build(BuildContext context) => FondoValle(
        appBar: AppBar(title: const Text('Mis documentos')),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: const [MisDocumentos()]),
      );
}
