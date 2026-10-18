import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../services/api_error.dart';
import '../utils/contacto.dart';
import 'ui/ui.dart';

/// Para quién es el panel: cambia los textos ("tu negocio" / "tu perfil de repartidor")
enum TipoSolicitud { negocio, repartidor }

/// Estado de la solicitud de un vendedor o repartidor mientras NO está aprobado: pendiente, rechazado o
/// suspendido, con el motivo que escribió el administrador y qué puede hacer ahora.
///   * pendiente: los pasos de la revisión y qué adelantar mientras tanto.
///   * rechazado: el motivo, corregir los datos y pedir una nueva revisión.
///   * suspendido: el motivo y escribir a soporte (volver lo decide el administrador).
/// Se recarga solo cuando llega el aviso de la decisión (lo maneja la pantalla que lo usa, con [onActualizar]).
class PanelAprobacion extends StatefulWidget {
  const PanelAprobacion({
    super.key,
    required this.tipo,
    required this.aprobacion,
    this.motivo,
    this.soporte,
    this.textoCorregir,
    this.onCorregir,
    this.textoMientras,
    this.onMientras,
    required this.onPedirRevision,
    required this.onActualizar,
    this.extra,
  });

  final TipoSolicitud tipo;
  final String aprobacion; // 'pendiente' | 'rechazado' | 'suspendido'
  final String? motivo;
  final String? soporte;

  /// Rechazado: botón para ir a corregir los datos ("Corregir mi negocio")
  final String? textoCorregir;
  final VoidCallback? onCorregir;

  /// Pendiente: algo útil para adelantar mientras esperan ("Armar mi menú")
  final String? textoMientras;
  final VoidCallback? onMientras;

  /// Contenido propio del tipo de solicitud (el repartidor: sus documentos), debajo de los pasos
  final Widget? extra;

  final Future<void> Function() onPedirRevision;
  final Future<void> Function() onActualizar;

  @override
  State<PanelAprobacion> createState() => _PanelAprobacionState();
}

class _PanelAprobacionState extends State<PanelAprobacion> {
  bool _pidiendo = false;

  bool get _esNegocio => widget.tipo == TipoSolicitud.negocio;

  Future<void> _pedirRevision() async {
    setState(() => _pidiendo = true);
    try {
      await widget.onPedirRevision();
      HapticFeedback.mediumImpact();
      if (mounted) mostrarMensaje(context, 'Listo: enviamos tu solicitud de nuevo. Te avisaremos cuando la revisen');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _pidiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final (icono, color, titulo, mensaje) = switch (widget.aprobacion) {
      'rechazado' => (
          Icons.assignment_late_rounded,
          AppTheme.errorColor,
          'Tu solicitud no fue aprobada',
          _esNegocio
              ? 'Revisamos los datos de tu negocio y hay algo que corregir. Arréglalo y pide una nueva revisión.'
              : 'Revisamos tu perfil de repartidor y hay algo que corregir. Arréglalo y pide una nueva revisión.',
        ),
      'suspendido' => (
          Icons.block_rounded,
          AppTheme.errorColor,
          _esNegocio ? 'Tu negocio está suspendido' : 'Tu cuenta de repartidor está suspendida',
          _esNegocio
              ? 'Por ahora tu negocio no aparece en la app ni recibe pedidos. Escríbenos para revisarlo juntos.'
              : 'Por ahora no puedes conectarte ni recibir pedidos. Escríbenos para revisarlo juntos.',
        ),
      _ => (
          Icons.hourglass_top_rounded,
          AppTheme.warningColor,
          'Estamos revisando tu solicitud',
          _esNegocio
              ? 'Nuestro equipo verifica los datos de tu negocio. Te avisaremos por notificación y por correo apenas esté aprobado.'
              : 'Nuestro equipo verifica tus datos y tu vehículo. Te avisaremos por notificación y por correo apenas estés aprobado.',
        ),
    };

    return RefreshIndicator(
      onRefresh: widget.onActualizar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Aparecer(
            child: Column(
              children: [
                _IconoLatiendo(icono: icono, color: color, latir: widget.aprobacion == 'pendiente'),
                const SizedBox(height: 20),
                Text(titulo, style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(mensaje, style: tema.bodyMedium?.copyWith(color: c.textoSuave), textAlign: TextAlign.center),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Motivo del administrador
          if (widget.motivo != null && widget.aprobacion != 'pendiente')
            Aparecer(
              indice: 1,
              child: TarjetaValle(
                color: color.withValues(alpha: 0.08),
                colorBorde: color.withValues(alpha: 0.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Motivo', style: tema.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(widget.motivo!, style: tema.bodyLarge),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Pasos de la revisión
          if (widget.aprobacion == 'pendiente')
            Aparecer(
              indice: 1,
              child: TarjetaValle(
                child: Column(
                  children: [
                    const _Paso(estado: _EstadoPaso.hecho, titulo: 'Solicitud enviada', detalle: 'Recibimos tus datos'),
                    const _Paso(estado: _EstadoPaso.enCurso, titulo: 'Revisión del equipo', detalle: 'Suele tomar menos de 24 horas'),
                    _Paso(
                      estado: _EstadoPaso.pendiente,
                      titulo: _esNegocio ? '¡A vender!' : '¡A repartir!',
                      detalle: _esNegocio ? 'Tu negocio aparece para los clientes' : 'Te conectas y recibes pedidos',
                      ultimo: true,
                    ),
                  ],
                ),
              ),
            ),
          if (widget.extra != null && widget.aprobacion != 'suspendido') ...[const SizedBox(height: 16), Aparecer(indice: 2, child: widget.extra!)],
          const SizedBox(height: 24),

          // Acciones
          if (widget.aprobacion == 'pendiente' && widget.onMientras != null) ...[
            Text(
              _esNegocio ? 'Mientras tanto, deja todo listo para tu primer pedido:' : 'Mientras tanto, revisa que tus datos estén bien:',
              style: tema.bodyMedium?.copyWith(color: c.textoSuave),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            BotonValle(texto: widget.textoMientras ?? 'Continuar', icono: Icons.arrow_forward_rounded, onPressed: widget.onMientras),
          ],
          if (widget.aprobacion == 'rechazado') ...[
            if (widget.onCorregir != null) ...[
              BotonValle(texto: widget.textoCorregir ?? 'Corregir mis datos', icono: Icons.edit_rounded, tipo: TipoBoton.secundario, onPressed: widget.onCorregir),
              const SizedBox(height: 12),
            ],
            BotonValle(texto: 'Pedir nueva revisión', icono: Icons.send_rounded, cargando: _pidiendo, onPressed: _pedirRevision),
          ],
          if (widget.soporte != null) ...[
            const SizedBox(height: 12),
            BotonValle(
              texto: 'Contactar a soporte',
              icono: Icons.support_agent_rounded,
              tipo: widget.aprobacion == 'suspendido' ? TipoBoton.principal : TipoBoton.texto,
              onPressed: () => escribirASoporte(
                context,
                widget.soporte!,
                asunto: _esNegocio ? 'Ayuda con la aprobación de mi negocio' : 'Ayuda con mi cuenta de repartidor',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ícono grande en un círculo; mientras está pendiente "late" despacio (algo está pasando)
class _IconoLatiendo extends StatefulWidget {
  const _IconoLatiendo({required this.icono, required this.color, required this.latir});

  final IconData icono;
  final Color color;
  final bool latir;

  @override
  State<_IconoLatiendo> createState() => _IconoLatiendoState();
}

class _IconoLatiendoState extends State<_IconoLatiendo> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.latir) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _IconoLatiendo anterior) {
    super.didUpdateWidget(anterior);
    if (widget.latir && !_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    if (!widget.latir) _ctrl.stop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, hijo) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.12),
            boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.25 * t), blurRadius: 24 * t, spreadRadius: 6 * t)],
          ),
          child: hijo,
        );
      },
      child: Icon(widget.icono, size: 52, color: widget.color),
    );
  }
}

enum _EstadoPaso { hecho, enCurso, pendiente }

/// Un paso de la línea de la revisión, con su conector hacia el siguiente
class _Paso extends StatelessWidget {
  const _Paso({required this.estado, required this.titulo, required this.detalle, this.ultimo = false});

  final _EstadoPaso estado;
  final String titulo;
  final String detalle;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final color = switch (estado) {
      _EstadoPaso.hecho => c.primario,
      _EstadoPaso.enCurso => AppTheme.warningColor,
      _EstadoPaso.pendiente => c.textoSuave,
    };
    final icono = switch (estado) {
      _EstadoPaso.hecho => Icons.check_rounded,
      _EstadoPaso.enCurso => Icons.more_horiz_rounded,
      _EstadoPaso.pendiente => Icons.flag_rounded,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: estado == _EstadoPaso.pendiente ? Colors.transparent : color.withValues(alpha: 0.18),
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icono, size: 16, color: color),
              ),
              if (!ultimo) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: c.borde)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: ultimo ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: estado == _EstadoPaso.pendiente ? c.textoSuave : null),
                  ),
                  Text(detalle, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
