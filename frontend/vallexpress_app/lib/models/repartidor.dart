import 'pedido.dart';

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// Perfil del repartidor: vehículo, si está en línea, calificación y entregas
class PerfilRepartidor {
  const PerfilRepartidor({
    required this.usuario,
    required this.vehiculo,
    this.placa,
    this.color,
    this.aprobacion = 'pendiente',
    this.disponible = false,
    this.calificacion = 0,
    this.numeroCalificaciones = 0,
    this.numeroEntregas = 0,
  });

  final String usuario;
  final Vehiculo vehiculo;
  final String? placa;
  final String? color;
  final String aprobacion;
  final bool disponible;
  final double calificacion;
  final int numeroCalificaciones;
  final int numeroEntregas;

  bool get aprobado => aprobacion == 'aprobado';

  factory PerfilRepartidor.desdeJson(Map<String, dynamic> j) => PerfilRepartidor(
        usuario: '${j['usuario'] ?? ''}',
        vehiculo: Vehiculo.deCodigo(j['vehiculo']?.toString()),
        placa: (j['placa'] ?? '').toString().isEmpty ? null : '${j['placa']}',
        color: (j['color'] ?? '').toString().isEmpty ? null : '${j['color']}',
        aprobacion: '${j['aprobacion'] ?? 'pendiente'}',
        disponible: j['disponible'] == true,
        calificacion: _num(j['calificacion']),
        numeroCalificaciones: (j['numeroCalificaciones'] as num?)?.toInt() ?? 0,
        numeroEntregas: (j['numeroEntregas'] as num?)?.toInt() ?? 0,
      );
}

/// Pedidos que el repartidor puede tomar: "listos" (ya) y "próximos" (el negocio los está preparando)
class PedidosLibres {
  const PedidosLibres({this.listos = const [], this.proximos = const [], this.enLinea = false});

  final List<Pedido> listos;
  final List<Pedido> proximos;
  final bool enLinea;

  factory PedidosLibres.desdeJson(Map<String, dynamic> j) => PedidosLibres(
        listos: (j['listos'] as List? ?? []).map((p) => Pedido.desdeJson(Map<String, dynamic>.from(p))).toList(),
        proximos: (j['proximos'] as List? ?? []).map((p) => Pedido.desdeJson(Map<String, dynamic>.from(p))).toList(),
        enLinea: j['enLinea'] == true,
      );
}
