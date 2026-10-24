import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/legal.dart';
import '../../services/api_error.dart';
import '../../services/legal_service.dart';
import '../../widgets/ui/ui.dart';

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
String fechaLegal(DateTime? d) => d == null ? '' : '${d.day} de ${_meses[d.month - 1]} de ${d.year}';

/// Abre un documento legal para leerlo
Future<void> abrirDocumentoLegal(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentoLegalScreen(id: id)));

/// Términos y condiciones o política de privacidad, con letra clara y por secciones. El texto viene del servidor
/// (siempre la versión vigente); también se puede abrir como página web.
class DocumentoLegalScreen extends StatefulWidget {
  const DocumentoLegalScreen({super.key, required this.id});

  final String id;

  @override
  State<DocumentoLegalScreen> createState() => _DocumentoLegalScreenState();
}

class _DocumentoLegalScreenState extends State<DocumentoLegalScreen> {
  DocumentoLegal? _doc;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final d = await LegalService.documento(widget.id);
      if (mounted) setState(() => _doc = d);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    final tema = Theme.of(context).textTheme;
    return FondoValle(
      anchoEscritorio: 900,
      appBar: AppBar(
        title: Text(d?.esPrivacidad == true ? 'Privacidad' : 'Términos y condiciones'),
        actions: [
          IconButton(
            tooltip: 'Abrir en el navegador',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => launchUrl(Uri.parse(LegalService.urlWeb(widget.id)), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      child: d == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar el documento', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 5, conImagen: false))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(d.titulo, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Versión ${d.version} · vigente desde el ${fechaLegal(d.vigencia)}', style: tema.bodySmall?.copyWith(color: context.colores.textoSuave)),
                const SizedBox(height: 12),
                TarjetaValle(child: TextoLegal(bloques: d.bloques)),
              ],
            ),
    );
  }
}

/// Dibuja los bloques de un documento legal: títulos, párrafos y listas, con **negrita**
class TextoLegal extends StatelessWidget {
  const TextoLegal({super.key, required this.bloques});

  final List<BloqueLegal> bloques;

  /// "Hola **mundo**" -> spans con la negrita
  static List<TextSpan> spans(String texto) {
    final partes = texto.split('**');
    return [for (final (i, p) in partes.indexed) if (p.isNotEmpty) TextSpan(text: p, style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null)];
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final cuerpo = tema.bodyMedium?.copyWith(height: 1.55);
    Widget texto(String t, {TextStyle? estilo}) => Text.rich(TextSpan(children: spans(t)), style: estilo ?? cuerpo);
    Widget punto(String marca, Widget hijo, {double sangria = 0}) => Padding(
          padding: EdgeInsets.only(left: sangria, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SizedBox(width: 22, child: Text(marca, style: cuerpo?.copyWith(color: context.colores.primario, fontWeight: FontWeight.w800))), Expanded(child: hijo)],
          ),
        );

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in bloques.indexed)
            switch (b.tipo) {
              TipoBloque.titulo => Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 18, bottom: 6),
                  child: texto(b.texto, estilo: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: context.colores.primario)),
                ),
              TipoBloque.parrafo => Padding(padding: const EdgeInsets.only(bottom: 10), child: texto(b.texto)),
              TipoBloque.lista => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (n, item) in b.items.indexed)
                        punto(
                          b.ordenada ? '${n + 1}.' : '•',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              texto(item.texto),
                              for (final s in item.sub) punto('–', texto(s)),
                              for (final nota in item.notas) Padding(padding: const EdgeInsets.only(top: 4), child: texto(nota)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            },
        ],
      ),
    );
  }
}
