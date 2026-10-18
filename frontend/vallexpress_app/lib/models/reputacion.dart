double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
DateTime? _fecha(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Una calificación al repartidor: de un cliente o de un negocio. "autor" solo llega al administrador.
class CalificacionRepartidor {
  const CalificacionRepartidor({required this.pedidoId, required this.origen, required this.puntuacion, this.comentario, this.fecha, this.autor});

  final int pedidoId;
  final String origen; // cliente | negocio
  final int puntuacion;
  final String? comentario;
  final DateTime? fecha;
  final String? autor;

  factory CalificacionRepartidor.desdeJson(Map<String, dynamic> j) => CalificacionRepartidor(
        pedidoId: (j['pedidoId'] as num).toInt(),
        origen: '${j['origen'] ?? 'cliente'}',
        puntuacion: (j['puntuacion'] as num).toInt(),
        comentario: j['comentario']?.toString(),
        fecha: _fecha(j['fecha']),
        autor: j['autor']?.toString(),
      );
}

/// Advertencia del administrador al repartidor por su servicio
class Advertencia {
  const Advertencia({required this.id, required this.motivo, this.fecha});

  final int id;
  final String motivo;
  final DateTime? fecha;

  factory Advertencia.desdeJson(Map<String, dynamic> j) => Advertencia(id: (j['id'] as num).toInt(), motivo: '${j['motivo'] ?? ''}', fecha: _fecha(j['fecha']));
}

/// Lo que opinan del repartidor los clientes y los negocios, y las advertencias que recibió
class Reputacion {
  const Reputacion({
    required this.promedio,
    required this.total,
    required this.promedioClientes,
    required this.totalClientes,
    required this.promedioNegocios,
    required this.totalNegocios,
    required this.bajas,
    required this.calificaciones,
    required this.advertencias,
  });

  final double promedio;
  final int total;
  final double promedioClientes;
  final int totalClientes;
  final double promedioNegocios;
  final int totalNegocios;
  final int bajas; // de 1 o 2 estrellas
  final List<CalificacionRepartidor> calificaciones;
  final List<Advertencia> advertencias;

  factory Reputacion.desdeJson(Map<String, dynamic> j) => Reputacion(
        promedio: _num(j['promedio']),
        total: (j['total'] as num?)?.toInt() ?? 0,
        promedioClientes: _num(j['clientes']?['promedio']),
        totalClientes: (j['clientes']?['total'] as num?)?.toInt() ?? 0,
        promedioNegocios: _num(j['negocios']?['promedio']),
        totalNegocios: (j['negocios']?['total'] as num?)?.toInt() ?? 0,
        bajas: (j['bajas'] as num?)?.toInt() ?? 0,
        calificaciones: (j['calificaciones'] as List? ?? []).map((c) => CalificacionRepartidor.desdeJson(Map<String, dynamic>.from(c))).toList(),
        advertencias: (j['advertencias'] as List? ?? []).map((a) => Advertencia.desdeJson(Map<String, dynamic>.from(a))).toList(),
      );
}
