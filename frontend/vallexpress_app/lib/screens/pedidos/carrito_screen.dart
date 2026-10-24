import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/direccion.dart';
import '../../models/negocio.dart';
import '../../models/pedido.dart';
import '../../providers/carrito_provider.dart';
import '../../services/address_service.dart';
import '../../services/api_error.dart';
import '../../services/pedidos_service.dart';
import '../../utils/formato.dart';
import '../../widgets/ui/ui.dart';
import '../catalogo/negocio_detalle_screen.dart';
import '../profile/addresses_screen.dart';
import 'pedido_detalle_screen.dart';

/// Carrito: productos (con cantidad y nota), dirección de entrega, forma de pago, indicaciones y resumen.
/// El total es una estimación: al hacer el pedido el servidor calcula los precios reales.
class CarritoScreen extends StatefulWidget {
  const CarritoScreen({super.key});

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  final _notas = TextEditingController();
  List<Direccion> _direcciones = [];
  Direccion? _direccion;
  List<MetodoPago> _metodos = const [MetodoPago('efectivo', 'Efectivo')];
  String _metodo = 'efectivo';
  bool _cargando = true;
  bool _enviando = false;

  // Envío real a la dirección elegida (lo calcula ValleXpress por distancia); null mientras se cotiza
  ({double costoEnvio, double? distanciaKm, bool fueraDeCobertura, double radioKm})? _envio;
  bool _cotizando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait([AddressService.listar(), PedidosService.metodosPago()]);
      if (!mounted) return;
      final direcciones = r[0].map((d) => Direccion.desdeJson(Map<String, dynamic>.from(d))).toList();
      setState(() {
        _direcciones = direcciones;
        _direccion =
            direcciones.where((d) => d.id == _direccion?.id).firstOrNull ?? direcciones.where((d) => d.esPredeterminada).firstOrNull ?? direcciones.firstOrNull;
        _metodos = r[1] as List<MetodoPago>;
        if (!_metodos.any((m) => m.codigo == _metodo) && _metodos.isNotEmpty) _metodo = _metodos.first.codigo;
      });
      _cotizar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirDireccion() async {
    final elegida = await mostrarHoja<Object>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿A dónde lo llevamos?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final d in _direcciones)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TarjetaValle(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    colorBorde: d.id == _direccion?.id ? ctx.colores.primario : null,
                    onTap: () => Navigator.pop(ctx, d),
                    child: Row(
                      children: [
                        Icon(d.tipo.icono, color: ctx.colores.primario),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.titulo, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              Text(
                                d.direccion,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: ctx.colores.textoSuave),
                              ),
                            ],
                          ),
                        ),
                        if (d.id == _direccion?.id) Icon(Icons.check_circle_rounded, color: ctx.colores.primario),
                      ],
                    ),
                  ),
                ),
              BotonValle(
                texto: 'Agregar o editar direcciones',
                icono: Icons.add_location_alt_outlined,
                tipo: TipoBoton.secundario,
                onPressed: () => Navigator.pop(ctx, 'gestionar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (elegida is Direccion) {
      setState(() => _direccion = elegida);
      _cotizar();
    }
    if (elegida == 'gestionar') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressesScreen()));
      await _cargar();
    }
  }

  Future<void> _cotizar() async {
    final negocio = context.read<CarritoProvider>().negocio;
    final d = _direccion;
    if (negocio == null || d == null) return;
    setState(() => _cotizando = true);
    try {
      final e = await PedidosService.cotizar(negocioId: negocio.id, direccionId: int.parse(d.id));
      if (mounted && _direccion?.id == d.id) setState(() => _envio = e);
    } catch (_) {
      if (mounted) setState(() => _envio = null); // sin conexión: se muestra la estimación del negocio
    } finally {
      if (mounted) setState(() => _cotizando = false);
    }
  }

  double _costoEnvio(CarritoProvider carrito) => _envio?.costoEnvio ?? carrito.costoEnvio;
  double _total(CarritoProvider carrito) => carrito.subtotal + _costoEnvio(carrito);
  bool get _fuera => _envio?.fueraDeCobertura == true;

  // Si el negocio no recibe transferencias, queda efectivo aunque antes se haya elegido transferencia
  String _metodoElegido(Negocio n) => _metodo == 'transferencia' && !n.aceptaTransferencia ? 'efectivo' : _metodo;

  Future<void> _pedir(CarritoProvider carrito) async {
    if (_direccion == null) return _elegirDireccion();
    setState(() => _enviando = true);
    try {
      final pedido = await PedidosService.crear(
        negocioId: carrito.negocio!.id,
        direccionId: int.parse(_direccion!.id),
        metodoPago: _metodoElegido(carrito.negocio!),
        productos: carrito.paraEnviar(),
        notas: _notas.text,
      );
      if (!mounted) return;
      carrito.vaciar();
      final nav = Navigator.of(context);
      nav.popUntil((r) => r.isFirst);
      nav.push(
        MaterialPageRoute(
          builder: (_) => PedidoDetalleScreen(pedidoId: pedido.id, inicial: pedido, recienHecho: true),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        mostrarError(context, textoDeError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CarritoProvider>();
    final c = context.colores;
    final tema = Theme.of(context).textTheme;

    if (carrito.vacio && esEscritorio(context)) {
      return PaginaEscritorio(
        titulo: 'Tu carrito',
        subtitulo: 'Aquí verás lo que vas a pedir',
        icono: Icons.shopping_bag_rounded,
        conAtras: Navigator.canPop(context),
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: TarjetaValle(
            padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.shopping_bag_outlined, size: 44, color: Color(0xFFB07A00)),
                ),
                const SizedBox(height: 20),
                Text('Tu carrito está vacío', style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Entra a un negocio, elige lo que quieras y aparecerá aquí.', style: tema.bodyLarge?.copyWith(color: c.textoSuave)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.storefront_rounded),
                  label: const Text('Ver negocios'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (carrito.vacio) {
      return FondoValle(
        titulo: 'Tu carrito',
        child: EstadoVacio(
          icono: Icons.shopping_cart_outlined,
          titulo: 'Tu carrito está vacío',
          mensaje: 'Entra a un negocio y agrega lo que necesites.',
          textoAccion: 'Volver',
          onAccion: () => Navigator.pop(context),
        ),
      );
    }

    final n = carrito.negocio!;
    final falta = carrito.faltaParaMinimo;
    final recibe = n.abiertoAhora && n.aceptaPedidos;

    final vaciar = TextButton(
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Vaciar el carrito?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vaciar')),
            ],
          ),
        );
        if (ok == true) carrito.vaciar();
      },
      child: const Text('Vaciar'),
    );
    final hacerPedido = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (falta > 0 || !recibe)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              !recibe
                  ? '${n.nombre} no está recibiendo pedidos en este momento'
                  : 'Agrega ${Formato.dinero(falta)} más para llegar al pedido mínimo (${Formato.dinero(n.pedidoMinimo)})',
              textAlign: TextAlign.center,
              style: tema.bodySmall?.copyWith(color: AppTheme.warningColor, fontWeight: FontWeight.w600),
            ),
          ),
        BotonValle(
          texto: _direccion == null && !_cargando
              ? 'Elige a dónde llevarlo'
              : _fuera
              ? 'Fuera del área de entrega'
              : 'Hacer pedido · ${Formato.dinero(_total(carrito))}',
          icono: Icons.check_rounded,
          cargando: _enviando,
          onPressed: (_cargando || _cotizando || _fuera || falta > 0 || !recibe) ? null : () => _pedir(carrito),
        ),
      ],
    );
    final productos = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ImagenRed(url: n.logo, ancho: 44, alto: 44, radio: 12, icono: n.categoria.icono),
            const SizedBox(width: 12),
            Expanded(
              child: Text(n.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NegocioDetalleScreen(negocio: n))),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar más'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TarjetaValle(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final (i, item) in carrito.items.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.borde, indent: 16, endIndent: 16),
                _LineaCarrito(item: item, carrito: carrito),
              ],
            ],
          ),
        ),
      ],
    );
    final entrega = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoSeccion('Entrega'),
        TarjetaValle(
          onTap: _cargando ? null : _elegirDireccion,
          child: Row(
            children: [
              Icon(_direccion?.tipo.icono ?? Icons.add_location_alt_outlined, color: c.primario),
              const SizedBox(width: 12),
              Expanded(
                child: _cargando
                    ? const LinearProgressIndicator()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_direccion?.titulo ?? 'Agrega una dirección de entrega', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          if (_direccion != null)
                            Text(
                              _direccion!.direccion,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tema.bodySmall?.copyWith(color: c.textoSuave),
                            ),
                        ],
                      ),
              ),
              Text('Cambiar', style: tema.labelLarge?.copyWith(color: c.primario)),
            ],
          ),
        ),
        if (_fuera) ...[
          const SizedBox(height: 10),
          InsigniaValle(
            'Esta dirección está fuera del área de entrega de ${n.nombre} (hasta ${_envio!.radioKm.toStringAsFixed(0)} km). Elige otra dirección',
            color: AppTheme.errorColor,
            icono: Icons.wrong_location_outlined,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: c.textoSuave),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Llega en unos ${n.tiempoPreparacion + 15} min', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
            ),
          ],
        ),
      ],
    );
    final pago = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoSeccion('¿Cómo vas a pagar?'),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            // Transferencia solo si el negocio registró cuentas para recibirla
            for (final m in _metodos.where((m) => m.codigo != 'transferencia' || n.aceptaTransferencia))
              ChoiceChip(
                avatar: Icon(m.icono, size: 18, color: _metodoElegido(n) == m.codigo ? Colors.white : c.textoSuave),
                label: Text(m.descripcion),
                selected: _metodoElegido(n) == m.codigo,
                showCheckmark: false,
                labelStyle: TextStyle(color: _metodoElegido(n) == m.codigo ? Colors.white : c.texto, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _metodo = m.codigo),
              ),
          ],
        ),
        if (_metodoElegido(n) == 'efectivo') ...[
          const SizedBox(height: 8),
          Text(
            'Pagas al recibir. Ten el monto exacto si puedes.${!n.aceptaTransferencia && _metodos.any((m) => m.codigo == 'transferencia') ? ' Este negocio todavía no recibe transferencias.' : ''}',
            style: tema.bodySmall?.copyWith(color: c.textoSuave),
          ),
        ] else if (_metodoElegido(n) == 'transferencia') ...[
          const SizedBox(height: 8),
          Text(
            'Cuando el negocio confirme tu pedido verás sus cuentas: transfieres y subes la foto del comprobante. Así no pagas algo que no te puedan atender.',
            style: tema.bodySmall?.copyWith(color: c.textoSuave),
          ),
        ],
      ],
    );
    final indicaciones = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoSeccion('Indicaciones (opcional)'),
        TextField(
          controller: _notas,
          maxLength: 300,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej: tocar el timbre, casa de dos pisos', prefixIcon: Icon(Icons.chat_bubble_outline_rounded)),
        ),
      ],
    );
    final resumen = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoSeccion('Resumen'),
        TarjetaValle(
          child: Column(
            children: [
              _FilaMonto('Productos', carrito.subtotal),
              const SizedBox(height: 8),
              _FilaMonto(
                _envio?.distanciaKm != null ? 'Envío (${_envio!.distanciaKm!.toStringAsFixed(1)} km)' : 'Envío',
                _costoEnvio(carrito),
                gratis: _costoEnvio(carrito) == 0,
                cargando: _cotizando,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: c.borde),
              ),
              _FilaMonto('Total', _total(carrito), destacado: true),
            ],
          ),
        ),
      ],
    );

    // Computador: a la izquierda lo que lleva y a dónde; a la derecha cómo paga, el resumen y el botón
    if (esEscritorio(context)) {
      return PaginaEscritorio(
        titulo: 'Tu carrito',
        subtitulo: 'Pedido a ${n.nombre}',
        icono: Icons.shopping_bag_rounded,
        conAtras: true,
        acciones: [vaciar],
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [productos, const SizedBox(height: 16), entrega, const SizedBox(height: 16), indicaciones]),
            ),
            const SizedBox(width: 32),
            SizedBox(
              width: 400,
              child: TarjetaValle(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [pago, resumen, const SizedBox(height: 20), hacerPedido]),
              ),
            ),
          ],
        ),
      );
    }

    return FondoValle(
      titulo: 'Tu carrito',
      acciones: [vaciar],
      barraInferior: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: c.tarjeta,
            border: Border(top: BorderSide(color: c.borde)),
          ),
          child: hacerPedido,
        ),
      ),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [productos, entrega, pago, indicaciones, resumen]),
    );
  }
}

class _LineaCarrito extends StatelessWidget {
  const _LineaCarrito({required this.item, required this.carrito});

  final ItemCarrito item;
  final CarritoProvider carrito;

  Future<void> _editarNota(BuildContext context) async {
    final ctrl = TextEditingController(text: item.notas ?? '');
    final nota = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nota para ${item.producto.nombre}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej: sin cebolla'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (nota != null) carrito.fijarNotas(item.producto.id, nota);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final p = item.producto;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImagenRed(url: p.miniatura ?? p.imagen, ancho: 56, alto: 56, radio: 12, icono: Icons.fastfood_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  Formato.dinero(item.subtotal),
                  style: tema.bodyMedium?.copyWith(color: c.primario, fontWeight: FontWeight.w700),
                ),
                InkWell(
                  onTap: () => _editarNota(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      item.notas ?? '+ Agregar nota',
                      style: tema.bodySmall?.copyWith(
                        color: item.notas == null ? c.textoSuave : c.texto,
                        fontStyle: item.notas == null ? null : FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SelectorCantidad(cantidad: item.cantidad, compacto: true, onCambiar: (v) => carrito.fijarCantidad(p.id, v)),
        ],
      ),
    );
  }
}

class _FilaMonto extends StatelessWidget {
  const _FilaMonto(this.etiqueta, this.monto, {this.destacado = false, this.gratis = false, this.cargando = false});

  final String etiqueta;
  final double monto;
  final bool destacado;
  final bool gratis;
  final bool cargando; // calculando el envío

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final estilo = destacado ? tema.titleMedium?.copyWith(fontWeight: FontWeight.w800) : tema.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(etiqueta, style: estilo)),
        if (cargando)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Text(gratis ? 'Gratis' : Formato.dinero(monto), style: estilo?.copyWith(color: gratis ? AppTheme.successColor : null)),
      ],
    );
  }
}
