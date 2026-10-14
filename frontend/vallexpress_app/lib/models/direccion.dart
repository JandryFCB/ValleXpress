import 'package:flutter/material.dart';

/// Tipos de dirección. El servidor los maneja como texto de 3 letras (DOM, TRA, FAM, OTR).
enum TipoDireccion {
  casa('DOM', 'Casa', Icons.home_rounded),
  trabajo('TRA', 'Trabajo', Icons.work_rounded),
  familiar('FAM', 'Familiar', Icons.family_restroom_rounded),
  otro('OTR', 'Otro', Icons.place_rounded);

  const TipoDireccion(this.codigo, this.etiqueta, this.icono);

  final String codigo;
  final String etiqueta;
  final IconData icono;

  static TipoDireccion deCodigo(String? codigo) =>
      TipoDireccion.values.firstWhere((t) => t.codigo == codigo, orElse: () => TipoDireccion.otro);
}

/// Una dirección de entrega del cliente.
class Direccion {
  const Direccion({
    required this.id,
    required this.direccion,
    required this.latitud,
    required this.longitud,
    this.nombre,
    this.tipo = TipoDireccion.casa,
    this.referencia,
    this.instrucciones,
    this.esPredeterminada = false,
  });

  final String id;
  final String? nombre;
  final TipoDireccion tipo;
  final String direccion;
  final String? referencia;
  final String? instrucciones;
  final double latitud;
  final double longitud;
  final bool esPredeterminada;

  /// Título que se muestra en la tarjeta: el nombre que le puso el usuario, o el del tipo ("Casa")
  String get titulo => (nombre != null && nombre!.trim().isNotEmpty) ? nombre! : tipo.etiqueta;

  factory Direccion.desdeJson(Map<String, dynamic> j) {
    double numero(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);
    String? texto(Object? v) => (v == null || '$v'.trim().isEmpty) ? null : '$v';
    return Direccion(
      id: '${j['id'] ?? ''}',
      nombre: texto(j['nombre']),
      tipo: TipoDireccion.deCodigo(j['tipo']?.toString()),
      direccion: '${j['direccion'] ?? ''}',
      referencia: texto(j['referencia']),
      instrucciones: texto(j['instrucciones']),
      latitud: numero(j['latitud']),
      longitud: numero(j['longitud']),
      esPredeterminada: (j['esPredeterminada'] ?? j['es_predeterminada']) == true,
    );
  }
}
