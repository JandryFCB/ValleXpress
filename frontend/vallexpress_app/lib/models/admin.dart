import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'negocio.dart';
import 'repartidor.dart';

DateTime? _fecha(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
Map<String, int> _conteo(Object? v) => v is Map ? v.map((k, n) => MapEntry('$k', (n as num).toInt())) : {};

/// Estado de aprobación de un negocio o repartidor, con su texto y color
enum Aprobacion {
  pendiente('pendiente', 'Pendiente', Icons.hourglass_top_rounded, AppTheme.warningColor),
  aprobado('aprobado', 'Aprobado', Icons.verified_rounded, AppTheme.successColor),
  rechazado('rechazado', 'Rechazado', Icons.block_rounded, AppTheme.errorColor),
  suspendido('suspendido', 'Suspendido', Icons.pause_circle_rounded, AppTheme.errorColor);

  const Aprobacion(this.codigo, this.etiqueta, this.icono, this.color);

  final String codigo;
  final String etiqueta;
  final IconData icono;
  final Color color;

  static Aprobacion deCodigo(String? c) => values.firstWhere((a) => a.codigo == c, orElse: () => pendiente);
}

/// Lo que el administrador ve al entrar: el día de hoy, la semana y lo que espera su revisión
class ResumenAdmin {
  const ResumenAdmin({
    required this.pedidosHoy,
    required this.entregadosHoy,
    required this.ventasHoy,
    this.comisionesHoy = 0,
    this.enviosHoy = 0,
    required this.semana,
    required this.enCurso,
    required this.mejores,
    required this.usuarios,
    required this.negocios,
    required this.repartidores,
    required this.repartidoresEnLinea,
    required this.pendientes,
    this.comprobantesPorRevisar = 0,
    this.cobradoHoy = 0,
    this.cobradoSemana = 0,
    this.correoConfigurado = true,
  });

  final int pedidosHoy;
  final int entregadosHoy;
  final double ventasHoy;
  final double comisionesHoy; // lo que ganó ValleXpress hoy (comisión de los negocios)
  final double enviosHoy; // lo que ganaron los repartidores hoy
  final List<({DateTime dia, int pedidos, double ventas, double comisiones})> semana;
  final Map<String, int> enCurso;
  final List<({int id, String nombre, int pedidos, double ventas})> mejores;
  final Map<String, int> usuarios;
  final Map<String, int> negocios;
  final Map<String, int> repartidores;
  final int repartidoresEnLinea;
  final int pendientes;
  final int comprobantesPorRevisar; // pagos de comisión que esperan tu revisión
  final double cobradoHoy; // comisiones que los negocios pagaron hoy (plata que entró)
  final double cobradoSemana;
  final bool correoConfigurado;

  int get totalEnCurso => enCurso.values.fold(0, (a, b) => a + b);
  int get totalUsuarios => usuarios.values.fold(0, (a, b) => a + b);
  double get ventasSemana => semana.fold(0, (a, d) => a + d.ventas);
  double get comisionesSemana => semana.fold(0, (a, d) => a + d.comisiones);

  factory ResumenAdmin.desdeJson(Map<String, dynamic> j) {
    final hoy = Map<String, dynamic>.from(j['hoy'] ?? {});
    final rep = Map<String, dynamic>.from(j['repartidores'] ?? {});
    return ResumenAdmin(
      pedidosHoy: (hoy['pedidos'] as num?)?.toInt() ?? 0,
      entregadosHoy: (hoy['entregados'] as num?)?.toInt() ?? 0,
      ventasHoy: _num(hoy['ventas']),
      comisionesHoy: _num(hoy['comisiones']),
      enviosHoy: _num(hoy['envios']),
      semana: [
        for (final d in (j['ultimos7Dias'] as List? ?? []))
          (dia: DateTime.parse('${d['dia']}'), pedidos: (d['pedidos'] as num).toInt(), ventas: _num(d['ventas']), comisiones: _num(d['comisiones'])),
      ],
      enCurso: _conteo(j['pedidosEnCurso']),
      mejores: [
        for (final m in (j['mejoresNegocios'] as List? ?? []))
          (id: (m['id'] as num).toInt(), nombre: '${m['nombre']}', pedidos: (m['pedidos'] as num).toInt(), ventas: _num(m['ventas'])),
      ],
      usuarios: _conteo(j['usuarios']),
      negocios: _conteo(j['negocios']),
      repartidores: _conteo(Map.of(rep)..remove('enLinea')),
      repartidoresEnLinea: (rep['enLinea'] as num?)?.toInt() ?? 0,
      pendientes: (j['pendientes'] as num?)?.toInt() ?? 0,
      comprobantesPorRevisar: (j['comprobantesPorRevisar'] as num?)?.toInt() ?? 0,
      cobradoHoy: _num((j['cobrado'] as Map?)?['hoy']),
      cobradoSemana: _num((j['cobrado'] as Map?)?['semana']),
      correoConfigurado: j['correoConfigurado'] != false,
    );
  }
}

/// Permisos de un perfil (cliente, vendedor, repartidor): si puede registrarse desde la app y, para vendedor y
/// repartidor, si nace aprobado o espera la revisión. Con sus cuentas y las solicitudes que esperan.
class PerfilPermisos {
  const PerfilPermisos({required this.rol, required this.registroAbierto, this.aprobacionAutomatica, this.cuentas = 0, this.activas = 0, this.pendientes = 0});

  final String rol;
  final bool registroAbierto;
  final bool? aprobacionAutomatica; // null = el perfil no pasa por aprobación (cliente)
  final int cuentas;
  final int activas;
  final int pendientes;

  bool get conAprobacion => aprobacionAutomatica != null;

  factory PerfilPermisos.desdeJson(Map<String, dynamic> j) {
    final cuentas = Map<String, dynamic>.from(j['cuentas'] ?? {});
    return PerfilPermisos(
      rol: '${j['rol']}',
      registroAbierto: j['registroAbierto'] == true,
      aprobacionAutomatica: j['aprobacionAutomatica'] is bool ? j['aprobacionAutomatica'] as bool : null,
      cuentas: (cuentas['total'] as num?)?.toInt() ?? 0,
      activas: (cuentas['activos'] as num?)?.toInt() ?? 0,
      pendientes: (j['pendientes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Datos de contacto de una cuenta (dueño de un negocio, repartidor)
class CuentaContacto {
  const CuentaContacto({required this.usuario, required this.nombre, this.apellido, this.email, this.telefono, this.activo = true});

  final String usuario;
  final String nombre;
  final String? apellido;
  final String? email;
  final String? telefono;
  final bool activo;

  String get nombreCompleto => [nombre, apellido].whereType<String>().where((s) => s.isNotEmpty).join(' ');

  static CuentaContacto? desdeJson(Object? j) {
    if (j is! Map) return null;
    return CuentaContacto(
      usuario: '${j['usuario']}',
      nombre: '${j['nombre'] ?? ''}',
      apellido: j['apellido']?.toString(),
      email: j['email']?.toString(),
      telefono: j['telefono']?.toString(),
      activo: j['activo'] != false,
    );
  }
}

/// Un negocio visto por el administrador: el negocio, su aprobación y su dueño
class NegocioAdmin {
  const NegocioAdmin({required this.negocio, required this.aprobacion, this.aprobadoEn, this.dueno});

  final Negocio negocio;
  final Aprobacion aprobacion;
  final DateTime? aprobadoEn;
  final CuentaContacto? dueno;

  factory NegocioAdmin.desdeJson(Map<String, dynamic> j) => NegocioAdmin(
        negocio: Negocio.desdeJson(j),
        aprobacion: Aprobacion.deCodigo(j['aprobacion']?.toString()),
        aprobadoEn: _fecha(j['aprobadoEn']),
        dueno: CuentaContacto.desdeJson(j['dueno']),
      );
}

/// Un repartidor visto por el administrador: su perfil (vehículo, placa, entregas) y su contacto
class RepartidorAdmin {
  const RepartidorAdmin({required this.perfil, required this.aprobacion, this.aprobadoEn, this.contacto});

  final PerfilRepartidor perfil;
  final Aprobacion aprobacion;
  final DateTime? aprobadoEn;
  final CuentaContacto? contacto;

  String get nombre => contacto?.nombreCompleto ?? perfil.usuario;

  factory RepartidorAdmin.desdeJson(Map<String, dynamic> j) => RepartidorAdmin(
        perfil: PerfilRepartidor.desdeJson(j),
        aprobacion: Aprobacion.deCodigo(j['aprobacion']?.toString()),
        aprobadoEn: _fecha(j['aprobadoEn']),
        contacto: CuentaContacto.desdeJson(j['contacto']),
      );
}

/// Una cuenta de la app (cualquier rol), para buscarla y bloquearla
class UsuarioAdmin {
  const UsuarioAdmin({
    required this.usuario,
    required this.nombre,
    this.apellido,
    this.email,
    this.telefono,
    required this.rol,
    required this.activo,
    this.estatus = 'activo',
    this.cedula,
    this.foto,
    this.ultimaConexion,
    this.creadoEn,
  });

  final String usuario;
  final String nombre;
  final String? apellido;
  final String? email;
  final String? telefono;
  final String rol;
  final bool activo;

  /// 'activo' | 'bloqueado' | 'inactivo' (dado de baja)
  final String estatus;
  final String? cedula;
  final String? foto;
  final DateTime? ultimaConexion;
  final DateTime? creadoEn;

  String get nombreCompleto => [nombre, apellido].whereType<String>().where((s) => s.isNotEmpty).join(' ');
  bool get esAdmin => rol == 'administrador';

  static const etiquetasRol = {'cliente': 'Cliente', 'vendedor': 'Vendedor', 'repartidor': 'Repartidor', 'administrador': 'Admin'};
  static const iconosRol = {
    'cliente': Icons.person_rounded,
    'vendedor': Icons.storefront_rounded,
    'repartidor': Icons.two_wheeler_rounded,
    'administrador': Icons.admin_panel_settings_rounded,
  };

  factory UsuarioAdmin.desdeJson(Map<String, dynamic> j) => UsuarioAdmin(
        usuario: '${j['usuario']}',
        nombre: '${j['nombre'] ?? ''}',
        apellido: j['apellido']?.toString(),
        email: j['email']?.toString(),
        telefono: j['telefono']?.toString(),
        rol: '${j['rol'] ?? 'cliente'}',
        activo: j['activo'] != false,
        estatus: '${j['estatus'] ?? (j['activo'] == false ? 'bloqueado' : 'activo')}',
        cedula: j['cedula']?.toString(),
        foto: j['foto']?.toString(),
        ultimaConexion: _fecha(j['ultimaConexion']),
        creadoEn: _fecha(j['creadoEn']),
      );

  (String, Color, IconData) get estadoVisible => switch (estatus) {
        'bloqueado' => ('Bloqueada', AppTheme.errorColor, Icons.block_rounded),
        'inactivo' => ('Dada de baja', AppTheme.warningColor, Icons.person_off_rounded),
        _ => ('Activa', AppTheme.successColor, Icons.check_circle_rounded),
      };

  static const coloresRol = {
    'cliente': AppTheme.clienteColor,
    'vendedor': AppTheme.vendedorColor,
    'repartidor': AppTheme.repartidorColor,
    'administrador': AppTheme.infoColor,
  };
  Color get colorRol => coloresRol[rol] ?? AppTheme.clienteColor;
}

/// Una página de resultados y si hay más
class Pagina<T> {
  const Pagina(this.items, {this.hayMas = false, this.total = 0});

  final List<T> items;
  final bool hayMas;
  final int total;
}

/// Un valor del detalle de una cifra: dinero, número o entregas
class ValorCifra {
  const ValorCifra(this.etiqueta, this.valor, this.formato);

  final String etiqueta;
  final num valor;
  final String formato; // dinero | numero | entregas

  factory ValorCifra.desdeJson(Map<String, dynamic> j) => ValorCifra('${j['etiqueta'] ?? ''}', (j['valor'] as num?) ?? 0, '${j['formato'] ?? 'numero'}');
}

/// Un movimiento (un pedido, un pago) o un total agrupado (un local, un repartidor)
class FilaCifra {
  const FilaCifra({required this.titulo, required this.detalle, required this.valor, required this.formato, required this.icono, this.pedidoId, this.estado, this.fecha, this.ocupado = false});

  final String titulo;
  final String detalle;
  final num valor;
  final String formato;
  final String icono; // pedido | local | repartidor | pago
  final int? pedidoId; // tocarla abre el pedido
  final String? estado;
  final DateTime? fecha;
  final bool ocupado; // repartidor llevando un pedido

  factory FilaCifra.desdeJson(Map<String, dynamic> j) => FilaCifra(
        titulo: '${j['titulo'] ?? ''}',
        detalle: '${j['detalle'] ?? ''}',
        valor: (j['valor'] as num?) ?? 0,
        formato: '${j['formato'] ?? 'numero'}',
        icono: '${j['icono'] ?? 'pedido'}',
        pedidoId: (j['pedidoId'] as num?)?.toInt(),
        estado: j['estado']?.toString(),
        fecha: j['fecha'] == null ? null : DateTime.tryParse('${j['fecha']}')?.toLocal(),
        ocupado: j['ocupado'] == true,
      );
}

/// Detalle de una cifra del resumen del administrador: total, cifras secundarias y movimientos por sección
class DetalleCifra {
  const DetalleCifra({required this.rango, required this.total, required this.resumen, required this.secciones});

  final String rango; // hoy | semana | mes | ahora
  final ValorCifra total;
  final List<ValorCifra> resumen;
  final List<({String titulo, List<FilaCifra> filas})> secciones;

  factory DetalleCifra.desdeJson(Map<String, dynamic> j) => DetalleCifra(
        rango: '${j['rango'] ?? 'hoy'}',
        total: ValorCifra.desdeJson(Map<String, dynamic>.from(j['total'] ?? {})),
        resumen: [for (final r in (j['resumen'] as List? ?? [])) ValorCifra.desdeJson(Map<String, dynamic>.from(r))],
        secciones: [
          for (final s in (j['secciones'] as List? ?? []))
            (titulo: '${s['titulo'] ?? ''}', filas: [for (final f in (s['filas'] as List? ?? [])) FilaCifra.desdeJson(Map<String, dynamic>.from(f))]),
        ],
      );
}
