import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/negocio.dart';
import '../../services/catalogo_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiempo_real.dart';
import '../../utils/sonido.dart';
import '../../widgets/panel_aprobacion.dart';
import '../../widgets/ui/ui.dart';
import '../../config/theme.dart';
import '../profile/perfil_screen.dart';
import 'mi_negocio_screen.dart';
import 'pedidos_negocio_screen.dart';

/// Inicio del vendedor: pestañas Pedidos, Mi negocio y Perfil. Un pedido nuevo vibra fuerte y avisa arriba aunque
/// esté en otra pestaña; la pestaña Pedidos muestra cuántos esperan respuesta. Mientras el negocio no esté
/// aprobado, la primera pestaña es "Solicitud" (en revisión, rechazado o suspendido, con el motivo).
class InicioVendedorScreen extends StatefulWidget {
  const InicioVendedorScreen({super.key});

  @override
  State<InicioVendedorScreen> createState() => _InicioVendedorScreenState();
}

class _InicioVendedorScreenState extends State<InicioVendedorScreen> {
  int _pestana = 0;
  int _porAceptar = 0;
  Negocio? _negocio;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    TiempoReal.instancia.iniciar();
    _subs.add(
      TiempoReal.instancia.avisos.listen((a) {
        if (!mounted) return;
        if (a.tipo == 'pedido_nuevo') {
          HapticFeedback.heavyImpact();
          sonarPedidoNuevo();
        }
        mostrarMensaje(context, a.tipo == 'pedido_nuevo' ? '🛒 ${a.titulo} ${a.mensaje}' : a.titulo);
        // La decisión del administrador sobre el negocio: se recarga al instante
        if (a.tipo.startsWith('negocio_')) {
          _cargarNegocio().then((_) {
            if (mounted && a.tipo == 'negocio_aprobado') Confeti.lanzar(context);
          });
        }
      }),
    );
    _subs.add(
      TiempoReal.instancia.cambios().listen((_) {
        _contar();
        if (_enRevision) _cargarNegocio(); // al volver a la app pudo haber llegado la decisión
      }),
    );
    _contar();
    _cargarNegocio();
  }

  bool get _enRevision => _negocio?.aprobacion != null && _negocio!.aprobacion != 'aprobado';

  Future<void> _cargarNegocio() async {
    try {
      final n = await CatalogoService.miNegocio();
      if (mounted) setState(() => _negocio = n);
    } catch (_) {
      // sin conexión: se queda con lo último que supo
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _contar() async {
    try {
      final r = await PedidosService.pedidosDelNegocio(estado: 'activos');
      final n = r.pedidos.where((p) => p.puedeCancelar).length; // pendientes de aceptar
      if (mounted) setState(() => _porAceptar = n);
    } catch (_) {
      // sin negocio todavía o sin conexión
    }
  }

  // Mientras no esté aprobado: el estado de la solicitud. "Armar mi menú" y "Corregir" llevan a Mi negocio.
  Widget _solicitud() {
    final n = _negocio!;
    return FondoValle(
      appBar: AppBar(title: const Text('Tu solicitud'), automaticallyImplyLeading: false),
      child: PanelAprobacion(
        tipo: TipoSolicitud.negocio,
        aprobacion: n.aprobacion!,
        motivo: n.motivoAprobacion,
        soporte: n.soporte,
        textoMientras: 'Armar mi negocio y mi menú',
        onMientras: () => setState(() => _pestana = 1),
        textoCorregir: 'Corregir mi negocio',
        onCorregir: () => setState(() => _pestana = 1),
        onPedirRevision: () async {
          final actualizado = await CatalogoService.pedirRevisionNegocio();
          if (mounted) setState(() => _negocio = actualizado);
        },
        onActualizar: _cargarNegocio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AtrasEnPestanas(
      pestana: _pestana,
      irAPrimera: () => setState(() => _pestana = 0),
      child: PestanasAdaptables(
        indice: _pestana,
        onCambiar: (i) {
          setState(() => _pestana = i);
          if (i == 0) _cargarNegocio(); // pudo crear o corregir su negocio en la otra pestaña
        },
        cabeceraLateral: _negocio == null ? null : _NegocioLateral(negocio: _negocio!),
        paginas: [
          _enRevision ? _solicitud() : const PedidosNegocioScreen(conFlechaAtras: false),
          const MiNegocioScreen(),
          const PerfilScreen(),
        ],
        destinos: [
          if (_enRevision)
            const Destino(icono: Icons.hourglass_empty_rounded, iconoActivo: Icons.hourglass_top_rounded, texto: 'Solicitud')
          else
            Destino(
              icono: Icons.receipt_long_outlined,
              iconoActivo: Icons.receipt_long_rounded,
              texto: 'Pedidos',
              insignia: _porAceptar,
              colorInsignia: AppTheme.warningColor,
            ),
          const Destino(icono: Icons.storefront_outlined, iconoActivo: Icons.storefront_rounded, texto: 'Mi negocio'),
          const Destino(icono: Icons.person_outline_rounded, iconoActivo: Icons.person_rounded, texto: 'Perfil'),
        ],
      ),
    );
  }
}

/// En el menú lateral del computador: logo, nombre y si el negocio está abierto
class _NegocioLateral extends StatelessWidget {
  const _NegocioLateral({required this.negocio});

  final Negocio negocio;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final abierto = negocio.abiertoAhora;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.tarjetaElevada, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          ImagenRed(url: negocio.logo, ancho: 40, alto: 40, radio: 12, icono: Icons.storefront_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(negocio.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  abierto ? '● Abierto' : 'Cerrado',
                  style: tema.labelMedium?.copyWith(color: abierto ? c.primario : c.textoSuave, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
