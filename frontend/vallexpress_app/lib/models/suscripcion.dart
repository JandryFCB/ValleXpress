import 'package:flutter/material.dart';
import '../config/theme.dart';

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
DateTime? _fecha(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Estado de un mes de la suscripción
enum EstadoMes {
  porPagar('por_pagar', 'Por pagar', Icons.schedule_rounded, AppTheme.warningColor),
  vencido('vencido', 'Vencido', Icons.error_outline_rounded, AppTheme.errorColor),
  enRevision('en_revision', 'En revisión', Icons.hourglass_top_rounded, AppTheme.infoColor),
  pagado('pagado', 'Pagado', Icons.check_circle_rounded, AppTheme.successColor),
  proximo('proximo', 'Próximo', Icons.event_rounded, Colors.grey);

  const EstadoMes(this.codigo, this.etiqueta, this.icono, this.color);
  final String codigo;
  final String etiqueta;
  final IconData icono;
  final Color color;

  static EstadoMes deCodigo(String? c) => values.firstWhere((e) => e.codigo == c, orElse: () => EstadoMes.porPagar);
}

/// Un pago de la suscripción: el comprobante que subió (en revisión, aprobado o rechazado) o el que registró el admin
class PagoSuscripcion {
  const PagoSuscripcion({required this.id, required this.estado, required this.monto, this.imagen, this.referencia, this.motivoRechazo, this.fecha, this.revisadoEn});

  final int id;
  final String estado; // enviado | aprobado | rechazado
  final double monto;
  final String? imagen;
  final String? referencia;
  final String? motivoRechazo;
  final DateTime? fecha;
  final DateTime? revisadoEn;

  bool get enviado => estado == 'enviado';
  bool get rechazado => estado == 'rechazado';

  factory PagoSuscripcion.desdeJson(Map<String, dynamic> j) => PagoSuscripcion(
        id: (j['id'] as num).toInt(),
        estado: '${j['estado'] ?? 'enviado'}',
        monto: _num(j['monto']),
        imagen: j['imagen']?.toString(),
        referencia: j['referencia']?.toString(),
        motivoRechazo: j['motivoRechazo']?.toString(),
        fecha: _fecha(j['fecha']),
        revisadoEn: _fecha(j['revisadoEn']),
      );
}

PagoSuscripcion? _pago(Object? v) => v is Map ? PagoSuscripcion.desdeJson(Map<String, dynamic>.from(v)) : null;

/// Un mes de la suscripción (de su primer día) con lo que cuesta y cómo va
class MesSuscripcion {
  const MesSuscripcion({required this.mes, required this.nombre, required this.monto, required this.vence, required this.estado, this.pago, this.comprobante, this.rechazado});

  final String mes; // AAAA-MM-01
  final String nombre; // noviembre 2026
  final double monto;
  final DateTime vence; // último día para pagar
  final EstadoMes estado;
  final PagoSuscripcion? pago; // aprobado
  final PagoSuscripcion? comprobante; // en revisión
  final PagoSuscripcion? rechazado; // el último rechazado (con el motivo)

  String get titulo => nombre.isEmpty ? mes : '${nombre[0].toUpperCase()}${nombre.substring(1)}';

  /// Se puede subir el comprobante: se debe (o se adelanta) y no hay uno en revisión
  bool get pagable => estado == EstadoMes.porPagar || estado == EstadoMes.vencido || estado == EstadoMes.proximo;

  factory MesSuscripcion.desdeJson(Map<String, dynamic> j) => MesSuscripcion(
        mes: '${j['mes']}',
        nombre: '${j['nombre'] ?? ''}',
        monto: _num(j['monto']),
        vence: DateTime.parse('${j['vence']}'),
        estado: EstadoMes.deCodigo(j['estado']?.toString()),
        pago: _pago(j['pago']),
        comprobante: _pago(j['comprobante']),
        rechazado: _pago(j['rechazado']),
      );
}

/// Cuenta de ValleXpress donde vendedores y repartidores transfieren su suscripción
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

  /// Lista de cuentas del servidor ("cuentas"); las versiones anteriores mandaban una sola ("cuenta")
  static List<CuentaCobro> listaDesdeJson(Map<String, dynamic> j) {
    if (j['cuentas'] is List) return [for (final c in j['cuentas'] as List) CuentaCobro.desdeJson(c)];
    final una = CuentaCobro.desdeJson(j['cuenta']);
    return una.banco.isEmpty && una.numero.isEmpty ? [] : [una];
  }

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

/// La suscripción mensual de un vendedor o repartidor: sus meses, lo que debe, si está bloqueado y a dónde transferir
class EstadoSuscripcion {
  const EstadoSuscripcion({
    required this.aplica,
    required this.meses,
    required this.saldoPendiente,
    required this.bloqueado,
    required this.diasGracia,
    required this.cuentas,
    this.tipo,
    this.cuota,
    this.vencidos = 0,
    this.enRevision = 0,
  });

  final bool aplica; // false: todavía no lo aprueban (no paga)
  final String? tipo; // vendedor | repartidor
  final double? cuota;
  final List<MesSuscripcion> meses; // del más nuevo al más viejo
  final double saldoPendiente; // por pagar + vencido (sin contar lo que está en revisión)
  final bool bloqueado; // tiene un mes vencido
  final int vencidos;
  final int enRevision;
  final int diasGracia; // hasta qué día del mes se paga
  final List<CuentaCobro> cuentas; // a dónde puede transferir (a la que le convenga)

  bool get alDia => !bloqueado && saldoPendiente <= 0;

  factory EstadoSuscripcion.desdeJson(Map<String, dynamic> j) => EstadoSuscripcion(
        aplica: j['aplica'] == true,
        tipo: j['tipo']?.toString(),
        cuota: j['cuota'] == null ? null : _num(j['cuota']),
        meses: (j['meses'] as List? ?? []).map((m) => MesSuscripcion.desdeJson(Map<String, dynamic>.from(m))).toList(),
        saldoPendiente: _num(j['saldoPendiente']),
        bloqueado: j['bloqueado'] == true,
        vencidos: (j['vencidos'] as num?)?.toInt() ?? 0,
        enRevision: (j['enRevision'] as num?)?.toInt() ?? 0,
        diasGracia: (j['diasGracia'] as num?)?.toInt() ?? 5,
        cuentas: CuentaCobro.listaDesdeJson(j),
      );
}

/// Para el administrador: un vendedor o repartidor que paga suscripción y cómo va
class Suscriptor {
  const Suscriptor({required this.usuario, required this.nombre, required this.tipo, required this.saldoPendiente, required this.bloqueado, this.cuota = 0, this.enRevision = 0, this.vencidos = 0, this.estadoMesActual = 'proximo'});

  final String usuario;
  final String nombre;
  final String tipo; // vendedor | repartidor
  final double cuota;
  final double saldoPendiente;
  final bool bloqueado;
  final int enRevision;
  final int vencidos;
  final String estadoMesActual;

  bool get alDia => !bloqueado && saldoPendiente <= 0;

  factory Suscriptor.desdeJson(Map<String, dynamic> j) => Suscriptor(
        usuario: '${j['usuario']}',
        nombre: '${j['nombre'] ?? ''}',
        tipo: '${j['tipo'] ?? 'vendedor'}',
        cuota: _num(j['cuota']),
        saldoPendiente: _num(j['saldoPendiente']),
        bloqueado: j['bloqueado'] == true,
        enRevision: (j['enRevision'] as num?)?.toInt() ?? 0,
        vencidos: (j['vencidos'] as num?)?.toInt() ?? 0,
        estadoMesActual: '${j['estadoMesActual'] ?? 'proximo'}',
      );
}

/// Para el administrador: un comprobante que espera revisión
class ComprobantePorRevisar {
  const ComprobantePorRevisar({required this.id, required this.usuario, required this.nombre, required this.tipo, required this.mes, required this.nombreMes, required this.monto, this.referencia, this.imagen, this.fecha});

  final int id;
  final String usuario;
  final String nombre;
  final String tipo;
  final String mes;
  final String nombreMes;
  final double monto;
  final String? referencia;
  final String? imagen;
  final DateTime? fecha;

  factory ComprobantePorRevisar.desdeJson(Map<String, dynamic> j) => ComprobantePorRevisar(
        id: (j['id'] as num).toInt(),
        usuario: '${j['usuario']}',
        nombre: '${j['nombre'] ?? ''}',
        tipo: '${j['tipo'] ?? 'vendedor'}',
        mes: '${j['mes']}',
        nombreMes: '${j['nombreMes'] ?? ''}',
        monto: _num(j['monto']),
        referencia: j['referencia']?.toString(),
        imagen: j['imagen']?.toString(),
        fecha: _fecha(j['fecha']),
      );
}

/// Configuración del cobro: cuotas, día límite, desde qué mes se cobra y la cuenta para transferir
class ConfigSuscripcion {
  const ConfigSuscripcion({required this.cuotaVendedor, required this.cuotaRepartidor, required this.diasGracia, required this.inicio, required this.cuentas});

  final double cuotaVendedor;
  final double cuotaRepartidor;
  final int diasGracia;
  final String inicio; // AAAA-MM-01
  final List<CuentaCobro> cuentas;

  factory ConfigSuscripcion.desdeJson(Map<String, dynamic> j) => ConfigSuscripcion(
        cuotaVendedor: _num(j['cuotaVendedor']),
        cuotaRepartidor: _num(j['cuotaRepartidor']),
        diasGracia: (j['diasGracia'] as num?)?.toInt() ?? 5,
        inicio: '${j['inicio'] ?? ''}',
        cuentas: CuentaCobro.listaDesdeJson(j),
      );
}
