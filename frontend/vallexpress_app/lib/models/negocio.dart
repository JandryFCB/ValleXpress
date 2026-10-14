import 'package:flutter/material.dart';

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
String? _texto(Object? v) => (v == null || '$v'.trim().isEmpty) ? null : '$v';

/// Categoría de negocio (Comida, Bebidas, Farmacia...). El código viene del servidor ('001', '099'...).
class Categoria {
  const Categoria(this.codigo, this.descripcion);

  final String codigo;
  final String descripcion;

  factory Categoria.desdeJson(Map<String, dynamic> j) => Categoria('${j['codigo']}', '${j['descripcion']}');

  /// Ícono para cada categoría conocida
  IconData get icono => switch (codigo) {
        '001' => Icons.restaurant_rounded,
        '002' => Icons.local_drink_rounded,
        '003' => Icons.icecream_rounded,
        '004' => Icons.bakery_dining_rounded,
        '005' => Icons.local_grocery_store_rounded,
        '006' => Icons.local_pharmacy_rounded,
        '007' => Icons.pets_rounded,
        _ => Icons.storefront_rounded,
      };
}

/// Horario de un día (1 = lunes ... 7 = domingo). Las horas van en texto 'HH:MM'.
class HorarioDia {
  const HorarioDia({required this.dia, this.cerrado = false, this.apertura, this.cierre});

  final int dia;
  final bool cerrado;
  final String? apertura;
  final String? cierre;

  static const nombres = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  String get nombreDia => nombres[dia - 1];
  String get texto => cerrado || apertura == null ? 'Cerrado' : '$apertura – $cierre';

  factory HorarioDia.desdeJson(Map<String, dynamic> j) => HorarioDia(
        dia: (j['dia'] as num).toInt(),
        cerrado: j['cerrado'] == true,
        apertura: _texto(j['apertura']),
        cierre: _texto(j['cierre']),
      );

  Map<String, dynamic> aJson() => cerrado ? {'dia': dia, 'cerrado': true} : {'dia': dia, 'cerrado': false, 'apertura': apertura, 'cierre': cierre};
}

/// Ubicación del local del negocio
class LocalNegocio {
  const LocalNegocio({required this.id, required this.direccion, required this.latitud, required this.longitud, this.referencia});

  final int id;
  final String direccion;
  final String? referencia;
  final double latitud;
  final double longitud;

  factory LocalNegocio.desdeJson(Map<String, dynamic> j) => LocalNegocio(
        id: (j['id'] as num).toInt(),
        direccion: '${j['direccion'] ?? ''}',
        referencia: _texto(j['referencia']),
        latitud: _num(j['latitud']),
        longitud: _num(j['longitud']),
      );
}

/// Un negocio. Los campos de "privados" (ruc, aprobación) solo llegan cuando lo pide su dueño.
class Negocio {
  const Negocio({
    required this.id,
    required this.nombre,
    required this.categoria,
    this.descripcion,
    this.logo,
    this.portada,
    this.costoEnvio = 0,
    this.pedidoMinimo = 0,
    this.tiempoPreparacion = 30,
    this.radioKm = 5,
    this.abierto = false,
    this.abiertoAhora = false,
    this.aceptaPedidos = true,
    this.calificacion = 0,
    this.numeroCalificaciones = 0,
    this.numeroPedidos = 0,
    this.local,
    this.horarios = const [],
    this.ruc,
    this.aprobacion,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final Categoria categoria;
  final String? logo;
  final String? portada;
  final double costoEnvio;
  final double pedidoMinimo;
  final int tiempoPreparacion;
  final double radioKm;
  final bool abierto;
  final bool abiertoAhora;
  final bool aceptaPedidos;
  final double calificacion;
  final int numeroCalificaciones;
  final int numeroPedidos;
  final LocalNegocio? local;
  final List<HorarioDia> horarios;
  final String? ruc;
  final String? aprobacion; // 'pendiente' | 'aprobado' | 'rechazado' | 'suspendido' (solo para el dueño)

  /// Horario de hoy (según el día del teléfono), o null si no hay horarios cargados
  HorarioDia? get horarioHoy {
    if (horarios.isEmpty) return null;
    final hoy = DateTime.now().weekday; // 1 = lunes
    return horarios.where((h) => h.dia == hoy).firstOrNull;
  }

  factory Negocio.desdeJson(Map<String, dynamic> j) => Negocio(
        id: (j['id'] as num).toInt(),
        nombre: '${j['nombre'] ?? ''}',
        descripcion: _texto(j['descripcion']),
        categoria: j['categoria'] is Map ? Categoria.desdeJson(Map<String, dynamic>.from(j['categoria'])) : const Categoria('099', 'Otros'),
        logo: _texto(j['logo']),
        portada: _texto(j['portada']),
        costoEnvio: _num(j['costoEnvio']),
        pedidoMinimo: _num(j['pedidoMinimo']),
        tiempoPreparacion: (j['tiempoPreparacion'] as num?)?.toInt() ?? 30,
        radioKm: _num(j['radioKm']),
        abierto: j['abierto'] == true,
        abiertoAhora: j['abiertoAhora'] == true,
        aceptaPedidos: j['aceptaPedidos'] != false,
        calificacion: _num(j['calificacion']),
        numeroCalificaciones: (j['numeroCalificaciones'] as num?)?.toInt() ?? 0,
        numeroPedidos: (j['numeroPedidos'] as num?)?.toInt() ?? 0,
        local: j['local'] is Map ? LocalNegocio.desdeJson(Map<String, dynamic>.from(j['local'])) : null,
        horarios: (j['horarios'] as List? ?? []).map((h) => HorarioDia.desdeJson(Map<String, dynamic>.from(h))).toList(),
        ruc: _texto(j['ruc']),
        aprobacion: _texto(j['aprobacion']),
      );
}
