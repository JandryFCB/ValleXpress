import 'package:flutter/material.dart';
import '../config/theme.dart';

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
DateTime? _fecha(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Estado de una semana de comisiones: en curso, pendiente, vencida, pagada o sin cargo
enum EstadoSemana {
  enCurso('en_curso', 'En curso', Icons.timelapse_rounded, AppTheme.infoColor),
  pendiente('pendiente', 'Por pagar', Icons.schedule_rounded, AppTheme.warningColor),
  vencida('vencida', 'Vencida', Icons.error_outline_rounded, AppTheme.errorColor),
  enRevision('en_revision', 'En revisión', Icons.hourglass_top_rounded, AppTheme.infoColor),
  pagada('pagada', 'Pagada', Icons.check_circle_rounded, AppTheme.successColor),
  sinCargo('sin_cargo', 'Sin comisión', Icons.remove_circle_outline_rounded, Colors.grey);

  const EstadoSemana(this.codigo, this.etiqueta, this.icono, this.color);
  final String codigo;
  final String etiqueta;
  final IconData icono;
  final Color color;

  static EstadoSemana deCodigo(String? c) => values.firstWhere((e) => e.codigo == c, orElse: () => EstadoSemana.pendiente);
}

/// Comprobante de transferencia que subió el negocio para pagar una semana
class ComprobantePago {
  const ComprobantePago({required this.id, required this.estado, this.imagen, this.referencia, this.motivoRechazo, this.fecha});

  final int id;
  final String estado; // enviado | aprobado | rechazado
  final String? imagen;
  final String? referencia;
  final String? motivoRechazo;
  final DateTime? fecha;

  bool get enviado => estado == 'enviado';
  bool get rechazado => estado == 'rechazado';

  factory ComprobantePago.desdeJson(Map<String, dynamic> j) => ComprobantePago(
        id: (j['id'] as num).toInt(),
        estado: '${j['estado'] ?? 'enviado'}',
        imagen: j['imagen']?.toString(),
        referencia: j['referencia']?.toString(),
        motivoRechazo: j['motivoRechazo']?.toString(),
        fecha: _fecha(j['fecha']),
      );
}

/// Cuenta de ValleXpress donde los negocios transfieren la comisión
class CuentaCobro {
  const CuentaCobro({this.banco = '', this.tipo = 'ahorros', this.numero = '', this.titular = '', this.identificacion = '', this.notas = '', this.completa = false});

  final String banco;
  final String tipo; // ahorros | corriente
  final String numero;
  final String titular;
  final String identificacion; // cédula o RUC del titular
  final String notas;
  final bool completa;

  String get tipoTexto => tipo == 'corriente' ? 'Corriente' : 'Ahorros';

  /// Para copiar y pegar en la app del banco
  String get paraCopiar => [
        if (banco.isNotEmpty) banco,
        'Cuenta de ${tipoTexto.toLowerCase()} $numero',
        if (titular.isNotEmpty) 'Titular: $titular',
        if (identificacion.isNotEmpty) 'Cédula/RUC: $identificacion',
      ].join('\n');

  Map<String, String> aJson() => {'banco': banco, 'tipo': tipo, 'numero': numero, 'titular': titular, 'identificacion': identificacion, 'notas': notas};

  factory CuentaCobro.desdeJson(Object? v) {
    final j = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{'notas': '${v ?? ''}'};
    return CuentaCobro(
      banco: '${j['banco'] ?? ''}',
      tipo: '${j['tipo'] ?? 'ahorros'}',
      numero: '${j['numero'] ?? ''}',
      titular: '${j['titular'] ?? ''}',
      identificacion: '${j['identificacion'] ?? ''}',
      notas: '${j['notas'] ?? ''}',
      completa: j['completa'] == true,
    );
  }
}

/// Una semana (lunes a domingo) de ventas de un negocio y la comisión de ValleXpress
class SemanaLiquidacion {
  const SemanaLiquidacion({
    required this.semana,
    required this.hasta,
    required this.pedidos,
    required this.ventas,
    required this.comision,
    required this.recibeNegocio,
    required this.estado,
    this.vence,
    this.fechaPago,
    this.referencia,
    this.comprobante,
  });

  final DateTime semana; // lunes
  final DateTime hasta; // domingo
  final int pedidos;
  final double ventas;
  final double comision;
  final double recibeNegocio;
  final EstadoSemana estado;
  final DateTime? vence;
  final DateTime? fechaPago;
  final String? referencia;
  final ComprobantePago? comprobante;

  bool get porPagar => estado == EstadoSemana.pendiente || estado == EstadoSemana.vencida || estado == EstadoSemana.enRevision;

  /// El negocio puede subir un comprobante (por pagar y sin uno en revisión)
  bool get puedeSubirComprobante => estado == EstadoSemana.pendiente || estado == EstadoSemana.vencida;

  /// El lunes en el formato que espera el servidor (AAAA-MM-DD)
  String get codigoSemana => '${semana.year}-${semana.month.toString().padLeft(2, '0')}-${semana.day.toString().padLeft(2, '0')}';

  factory SemanaLiquidacion.desdeJson(Map<String, dynamic> j) => SemanaLiquidacion(
        semana: DateTime.parse('${j['semana']}'),
        hasta: DateTime.parse('${j['hasta']}'),
        pedidos: (j['pedidos'] as num?)?.toInt() ?? 0,
        ventas: _num(j['ventas']),
        comision: _num(j['comision']),
        recibeNegocio: _num(j['recibeNegocio']),
        estado: EstadoSemana.deCodigo(j['estado']?.toString()),
        vence: _fecha(j['vence']),
        fechaPago: _fecha(j['fechaPago']),
        referencia: j['referencia']?.toString(),
        comprobante: j['comprobante'] is Map ? ComprobantePago.desdeJson(Map<String, dynamic>.from(j['comprobante'])) : null,
      );
}

/// Estado de cuenta de un negocio con ValleXpress
class EstadoDeCuenta {
  const EstadoDeCuenta({required this.semanas, required this.saldoPendiente, required this.bloqueado, required this.diasGracia, required this.cuenta});

  final List<SemanaLiquidacion> semanas;
  final double saldoPendiente;
  final bool bloqueado; // tiene una semana vencida: no recibe pedidos
  final int diasGracia;
  final CuentaCobro cuenta; // a dónde transferir

  factory EstadoDeCuenta.desdeJson(Map<String, dynamic> j) => EstadoDeCuenta(
        semanas: (j['semanas'] as List? ?? []).map((s) => SemanaLiquidacion.desdeJson(Map<String, dynamic>.from(s))).toList(),
        saldoPendiente: _num(j['saldoPendiente']),
        bloqueado: j['bloqueado'] == true,
        diasGracia: (j['diasGracia'] as num?)?.toInt() ?? 7,
        cuenta: CuentaCobro.desdeJson(j['cuenta']),
      );
}

/// Para el administrador: un negocio que debe semanas cerradas
class DeudaNegocio {
  const DeudaNegocio({required this.negocioId, required this.nombre, required this.semanas, required this.saldo, required this.bloqueado, this.porRevisar = 0});

  final int negocioId;
  final String nombre;
  final int semanas;
  final double saldo;
  final bool bloqueado;
  final int porRevisar; // comprobantes esperando revisión

  factory DeudaNegocio.desdeJson(Map<String, dynamic> j) => DeudaNegocio(
        negocioId: (j['negocioId'] as num).toInt(),
        nombre: '${j['nombre'] ?? ''}',
        semanas: (j['semanas'] as num?)?.toInt() ?? 0,
        saldo: _num(j['saldo']),
        bloqueado: j['bloqueado'] == true,
        porRevisar: (j['porRevisar'] as num?)?.toInt() ?? 0,
      );
}
