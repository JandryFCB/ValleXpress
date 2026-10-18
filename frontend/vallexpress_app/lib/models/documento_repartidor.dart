/// Un documento que el repartidor sube para que lo aprueben (cédula, selfie, licencia, matrícula)
class DocumentoRepartidor {
  const DocumentoRepartidor({required this.tipo, required this.titulo, required this.ayuda, required this.subido, this.url, this.miniatura, this.fecha});

  final String tipo; // cedula_frente | cedula_reverso | selfie | licencia | matricula
  final String titulo;
  final String ayuda;
  final bool subido;
  final String? url;
  final String? miniatura;
  final DateTime? fecha;

  factory DocumentoRepartidor.desdeJson(Map<String, dynamic> j) => DocumentoRepartidor(
        tipo: '${j['tipo']}',
        titulo: '${j['titulo'] ?? ''}',
        ayuda: '${j['ayuda'] ?? ''}',
        subido: j['subido'] == true,
        url: j['url']?.toString(),
        miniatura: j['miniatura']?.toString(),
        fecha: j['fecha'] == null ? null : DateTime.tryParse('${j['fecha']}')?.toLocal(),
      );
}

/// Los documentos que se le piden a un repartidor y si ya están completos
class DocumentosRepartidor {
  const DocumentosRepartidor({required this.documentos, required this.completos, required this.faltan, this.aprobacion = 'pendiente'});

  final List<DocumentoRepartidor> documentos;
  final bool completos;
  final int faltan;
  final String aprobacion; // estado de la cuenta del repartidor: pendiente | aprobado | rechazado | suspendido

  bool get aprobado => aprobacion == 'aprobado';

  factory DocumentosRepartidor.desdeJson(Map<String, dynamic> j) => DocumentosRepartidor(
        documentos: [for (final d in (j['documentos'] as List? ?? [])) DocumentoRepartidor.desdeJson(Map<String, dynamic>.from(d))],
        completos: j['completos'] == true,
        faltan: (j['faltan'] as num?)?.toInt() ?? 0,
        aprobacion: '${j['aprobacion'] ?? 'pendiente'}',
      );
}
