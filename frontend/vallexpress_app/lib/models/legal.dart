/// Un documento legal (términos de un perfil o política de privacidad). El servidor lo manda ya dividido en
/// bloques; el texto puede traer **negrita**.
class DocumentoLegal {
  const DocumentoLegal({required this.id, required this.titulo, required this.version, required this.vigencia, this.resumen = '', this.bloques = const []});

  final String id; // terminos-cliente | terminos-vendedor | terminos-repartidor | privacidad
  final String titulo;
  final String version;
  final DateTime? vigencia;
  final String resumen; // qué trata o qué cambió
  final List<BloqueLegal> bloques; // vacío en las listas (solo el resumen)

  bool get esPrivacidad => id == 'privacidad';

  factory DocumentoLegal.desdeJson(Map<String, dynamic> j) => DocumentoLegal(
        id: '${j['id']}',
        titulo: '${j['titulo'] ?? ''}',
        version: '${j['version'] ?? ''}',
        vigencia: DateTime.tryParse('${j['vigencia'] ?? ''}'),
        resumen: '${j['resumen'] ?? ''}',
        bloques: (j['bloques'] as List? ?? []).map((b) => BloqueLegal.desdeJson(Map<String, dynamic>.from(b))).toList(),
      );
}

enum TipoBloque { titulo, parrafo, lista }

class ItemLista {
  const ItemLista(this.texto, {this.sub = const [], this.notas = const []});

  final String texto;
  final List<String> sub; // sublista
  final List<String> notas; // párrafos que continúan el punto
}

class BloqueLegal {
  const BloqueLegal({required this.tipo, this.texto = '', this.ordenada = false, this.items = const []});

  final TipoBloque tipo;
  final String texto;
  final bool ordenada;
  final List<ItemLista> items;

  factory BloqueLegal.desdeJson(Map<String, dynamic> j) {
    final tipo = switch (j['tipo']) {
      'titulo' => TipoBloque.titulo,
      'lista' => TipoBloque.lista,
      _ => TipoBloque.parrafo,
    };
    List<String> textos(dynamic l) => (l as List? ?? []).map((e) => '$e').toList();
    return BloqueLegal(
      tipo: tipo,
      texto: '${j['texto'] ?? ''}',
      ordenada: j['ordenada'] == true,
      items: [for (final i in (j['items'] as List? ?? [])) ItemLista('${i['texto'] ?? ''}', sub: textos(i['sub']), notas: textos(i['notas']))],
    );
  }
}
