import 'package:flutter/material.dart';

/// Tipos de teléfono. El servidor los maneja como texto de 3 letras (MOV, CAS, TRA, WAP).
enum TipoTelefono {
  movil('MOV', 'Móvil', Icons.smartphone_rounded),
  casa('CAS', 'Casa', Icons.phone_rounded),
  trabajo('TRA', 'Trabajo', Icons.business_center_rounded),
  whatsapp('WAP', 'WhatsApp', Icons.chat_rounded);

  const TipoTelefono(this.codigo, this.etiqueta, this.icono);

  final String codigo;
  final String etiqueta;
  final IconData icono;

  static TipoTelefono deCodigo(String? codigo) =>
      TipoTelefono.values.firstWhere((t) => t.codigo == codigo, orElse: () => TipoTelefono.movil);
}

/// Un teléfono de la persona. El "id" es su secuencia dentro de la persona (1, 2, 3...).
class Telefono {
  const Telefono({
    required this.id,
    required this.numero,
    this.tipo = TipoTelefono.movil,
    this.principal = false,
    this.verificado = false,
  });

  final int id;
  final String numero;
  final TipoTelefono tipo;
  final bool principal;
  final bool verificado;

  factory Telefono.desdeJson(Map<String, dynamic> j) => Telefono(
        id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
        numero: '${j['numero'] ?? ''}',
        tipo: TipoTelefono.deCodigo(j['tipo']?.toString()),
        principal: j['principal'] == true,
        verificado: j['verificado'] == true,
      );
}
