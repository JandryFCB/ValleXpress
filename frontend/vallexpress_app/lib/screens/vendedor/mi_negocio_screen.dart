import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/direccion.dart';
import '../../models/negocio.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/formato.dart';
import '../../utils/imagen.dart';
import '../../widgets/ui/ui.dart';
import '../profile/address_picker_screen.dart';
import 'cuentas_negocio_screen.dart';
import 'horarios_screen.dart';
import '../suscripcion/mi_suscripcion_screen.dart';
import 'mis_productos_screen.dart';

/// Mi negocio (vendedor): abrir/cerrar, datos, entrega, ubicación, horario, logo, portada y acceso a los productos.
/// Si el vendedor todavía no tiene negocio, muestra el formulario para crearlo.
class MiNegocioScreen extends StatefulWidget {
  const MiNegocioScreen({super.key});

  @override
  State<MiNegocioScreen> createState() => _MiNegocioScreenState();
}

class _MiNegocioScreenState extends State<MiNegocioScreen> {
  bool _cargando = true;
  String? _error;
  Negocio? _negocio;
  List<Categoria> _categorias = [];
  bool _cambiandoEstado = false;
  String? _subiendo; // 'logo' | 'portada' mientras se sube una imagen

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _negocio == null;
      _error = null;
    });
    try {
      final r = await Future.wait<Object?>([CatalogoService.miNegocio(), CatalogoService.categorias()]);
      if (!mounted) return;
      setState(() {
        _negocio = r[0] as Negocio?;
        _categorias = r[1] as List<Categoria>;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = textoDeError(e);
        _cargando = false;
      });
    }
  }

  void _actualizar(Negocio n) => setState(() => _negocio = n);

  Future<void> _estado({bool? abierto, bool? aceptaPedidos}) async {
    setState(() => _cambiandoEstado = true);
    try {
      _actualizar(await CatalogoService.cambiarEstado(abierto: abierto, aceptaPedidos: aceptaPedidos));
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _cambiandoEstado = false);
    }
  }

  Future<void> _imagen(String tipo) async {
    final base64 = await elegirImagenBase64(context, titulo: tipo == 'logo' ? 'Logo del negocio' : 'Portada del negocio');
    if (base64 == null || !mounted) return;
    setState(() => _subiendo = tipo);
    try {
      _actualizar(await CatalogoService.subirImagenNegocio(tipo, base64));
      if (mounted) mostrarExito(context, tipo == 'logo' ? 'Logo actualizado' : 'Portada actualizada');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _subiendo = null);
    }
  }

  Future<void> _editar() async {
    final n = await mostrarHoja<Negocio>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormularioNegocio(negocio: _negocio!, categorias: _categorias),
    );
    if (n != null && mounted) {
      _actualizar(n);
      mostrarExito(context, 'Datos guardados');
    }
  }

  Future<void> _ubicacion() async {
    final l = _negocio!.local;
    final elegida = await Navigator.push<DireccionElegida>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressPickerScreen(
          paraLocal: true,
          actual: l == null ? null : Direccion(id: '${l.id}', direccion: l.direccion, referencia: l.referencia, latitud: l.latitud, longitud: l.longitud),
        ),
      ),
    );
    if (elegida == null || !mounted) return;
    try {
      _actualizar(
        await CatalogoService.fijarLocal(direccion: elegida.direccion, referencia: elegida.referencia, latitud: elegida.latitud, longitud: elegida.longitud),
      );
      if (mounted) mostrarExito(context, 'Ubicación guardada');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _horarios() async {
    final n = await Navigator.push<Negocio>(context, MaterialPageRoute(builder: (_) => HorariosScreen(actuales: _negocio!.horarios)));
    if (n != null && mounted) _actualizar(n);
  }

  @override
  Widget build(BuildContext context) {
    // Computador con el negocio cargado: página propia (título grande y dos columnas)
    if (esEscritorio(context) && !_cargando && _error == null && _negocio != null) return _contenido();
    return FondoValle(titulo: CatalogoService.gestionandoComoAdmin ? 'Gestionar negocio' : 'Mi negocio', child: _contenido());
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 3, altoImagen: 120, conImagen: false);
    if (_error != null) {
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        color: AppTheme.errorColor,
        titulo: 'No pudimos cargar tu negocio',
        mensaje: _error,
        textoAccion: 'Reintentar',
        onAccion: _cargar,
      );
    }
    if (_negocio == null) return _CrearNegocio(categorias: _categorias, onCreado: _actualizar);

    final n = _negocio!;
    final c = context.colores;
    final tema = Theme.of(context).textTheme;

    final escritorio = esEscritorio(context);

    // ------------------------------ Portada y logo ------------------------------
    final portada = TarjetaValle(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SizedBox(
            height: escritorio ? 190 : 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                n.portada != null
                    ? ImagenRed(url: n.portada, radio: 0)
                    : Container(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [c.primario.withValues(alpha: 0.4), c.acento.withValues(alpha: 0.3)])),
                      ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: _BotonCamara(cargando: _subiendo == 'portada', texto: 'Portada', onTap: () => _imagen('portada')),
                ),
                Positioned(
                  left: 16,
                  bottom: 12,
                  child: GestureDetector(
                    onTap: () => _imagen('logo'),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: c.tarjeta, width: 3),
                          ),
                          child: ImagenRed(url: n.logo, ancho: 72, alto: 72, radio: 15, icono: n.categoria.icono),
                        ),
                        Positioned(
                          right: -6,
                          bottom: -6,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: c.primario,
                            child: _subiendo == 'logo'
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.photo_camera_rounded, size: 15, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.nombre, style: tema.titleLarge),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          InsigniaValle(n.categoria.descripcion, color: AppTheme.infoColor, icono: n.categoria.icono),
                          if (n.aprobacion != null && n.aprobacion != 'aprobado')
                            switch (n.aprobacion) {
                              'rechazado' => const InsigniaValle('No aprobado', color: AppTheme.errorColor, icono: Icons.assignment_late_rounded),
                              'suspendido' => const InsigniaValle('Suspendido', color: AppTheme.errorColor, icono: Icons.block_rounded),
                              _ => const InsigniaValle('En revisión', color: AppTheme.warningColor, icono: Icons.hourglass_top_rounded),
                            },
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: _editar, icon: const Icon(Icons.edit_outlined), tooltip: 'Editar datos'),
              ],
            ),
          ),
        ],
      ),
    );

    // ------------------------------ Estado ------------------------------
    final estado = TarjetaValle(
      padding: EdgeInsets.zero,
      colorBorde: n.abiertoAhora ? AppTheme.successColor : null,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              n.abierto ? Icons.storefront_rounded : Icons.store_mall_directory_outlined,
              color: n.abierto ? AppTheme.successColor : c.textoSuave,
            ),
            title: Text(n.abierto ? 'Abierto' : 'Cerrado', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            subtitle: Text(
              !n.abierto
                  ? 'Los clientes te ven cerrado'
                  : (n.abiertoAhora ? 'Los clientes te ven abierto ahora' : 'Fuera de tu horario: los clientes te ven cerrado'),
            ),
            value: n.abierto,
            onChanged: _cambiandoEstado ? null : (v) => _estado(abierto: v),
          ),
          Divider(height: 1, color: c.borde),
          SwitchListTile(
            secondary: const Icon(Icons.receipt_long_outlined),
            title: const Text('Acepto pedidos'),
            subtitle: const Text('Apágalo si estás muy lleno, aunque sigas abierto'),
            value: n.aceptaPedidos,
            onChanged: _cambiandoEstado ? null : (v) => _estado(aceptaPedidos: v),
          ),
        ],
      ),
    );

    // ------------------------------ Resumen ------------------------------
    final resumen = Row(
      children: [
        Expanded(
          child: _Indicador(
            icono: Icons.star_rounded,
            color: AppTheme.accentColor,
            valor: n.numeroCalificaciones == 0 ? '—' : n.calificacion.toStringAsFixed(1),
            etiqueta: 'Calificación',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Indicador(icono: Icons.receipt_long_rounded, color: AppTheme.infoColor, valor: '${n.numeroPedidos}', etiqueta: 'Pedidos'),
        ),
      ],
    );

    // ------------------------------ Gestión ------------------------------
    final gestion = TarjetaValle(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Fila(
            icono: Icons.restaurant_menu_rounded,
            titulo: CatalogoService.gestionandoComoAdmin ? 'Productos' : 'Mis productos',
            valor: 'Menú, precios, stock e imágenes',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MisProductosScreen())),
          ),
          Divider(height: 1, indent: 70, color: c.borde),
          _Fila(
            icono: Icons.account_balance_rounded,
            titulo: 'Cuentas para transferencias',
            valor: n.aceptaTransferencia ? 'Tus clientes pueden pagarte por transferencia' : 'Sin cuentas: tus clientes solo pagan en efectivo',
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CuentasNegocioScreen()));
              _cargar();
            },
          ),
          Divider(height: 1, indent: 70, color: c.borde),
          if (!CatalogoService.gestionandoComoAdmin) ...[
            _Fila(
              icono: Icons.account_balance_wallet_outlined,
              titulo: 'Mi suscripción',
              valor: n.bloqueadoPorDeuda ? 'Tu suscripción está vencida: no recibes pedidos' : 'Cuota mensual y comprobantes',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MiSuscripcionScreen())),
            ),
            Divider(height: 1, indent: 70, color: c.borde),
          ],
          _Fila(
            icono: Icons.schedule_rounded,
            titulo: 'Horario',
            valor: n.horarios.isEmpty ? 'Sin horario: configúralo' : 'Hoy: ${n.horarioHoy?.texto ?? 'Cerrado'}',
            onTap: _horarios,
          ),
          Divider(height: 1, indent: 70, color: c.borde),
          _Fila(
            icono: Icons.location_on_outlined,
            titulo: 'Ubicación del local',
            valor: n.local?.direccion ?? 'Agrega dónde recogen los pedidos',
            onTap: _ubicacion,
          ),
          Divider(height: 1, indent: 70, color: c.borde),
          _Fila(
            icono: Icons.delivery_dining_outlined,
            titulo: 'Entrega',
            valor: 'Pedido mínimo ${Formato.dinero(n.pedidoMinimo)} · ${n.tiempoPreparacion} min · hasta ${n.radioKm.toStringAsFixed(0)} km',
            onTap: _editar,
          ),
        ],
      ),
    );

    // Computador: a la izquierda la tarjeta del negocio, si está abierto y sus cifras; a la derecha la gestión
    if (escritorio) {
      return PaginaEscritorio(
        titulo: CatalogoService.gestionandoComoAdmin ? 'Gestionar negocio' : 'Mi negocio',
        subtitulo: 'Cómo te ven los clientes, tu horario, tu local y tus cobros',
        icono: Icons.storefront_rounded,
        conAtras: CatalogoService.gestionandoComoAdmin,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [portada, const SizedBox(height: 16), estado, const SizedBox(height: 16), resumen],
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoSeccion('Tu negocio', subtitulo: 'Toca una opción para cambiarla'),
                  gestion,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          portada,
          const SizedBox(height: 12),
          estado,
          const SizedBox(height: 12),
          resumen,
          const SizedBox(height: 12),
          const EncabezadoSeccion('Tu negocio'),
          gestion,
        ],
      ),
    );
  }
}

class _BotonCamara extends StatelessWidget {
  const _BotonCamara({required this.cargando, required this.texto, required this.onTap});

  final bool cargando;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: cargando ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              cargando
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                texto,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.icono, required this.color, required this.valor, required this.etiqueta});

  final IconData icono;
  final Color color;
  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return TarjetaValle(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icono, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor, style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(etiqueta, style: tema.bodySmall?.copyWith(color: context.colores.textoSuave)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.icono, required this.titulo, required this.valor, required this.onTap});

  final IconData icono;
  final String titulo;
  final String valor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icono, size: 20, color: c.primario),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: tema.bodySmall?.copyWith(color: c.textoSuave),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textoSuave),
          ],
        ),
      ),
    );
  }
}

/// Primer paso para un vendedor sin negocio: nombre, categoría y descripción
class _CrearNegocio extends StatefulWidget {
  const _CrearNegocio({required this.categorias, required this.onCreado});

  final List<Categoria> categorias;
  final ValueChanged<Negocio> onCreado;

  @override
  State<_CrearNegocio> createState() => _CrearNegocioState();
}

class _CrearNegocioState extends State<_CrearNegocio> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  String _categoria = '001';
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_nombre.text.trim().length < 2) {
      mostrarError(context, 'Escribe el nombre de tu negocio');
      return;
    }
    setState(() => _guardando = true);
    try {
      final n = await CatalogoService.crearNegocio(
        nombre: _nombre.text.trim(),
        categoria: _categoria,
        descripcion: _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
      );
      if (!mounted) return;
      mostrarExito(context, '¡Tu negocio está listo!');
      widget.onCreado(n);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.storefront_rounded, size: 64, color: c.primario),
        const SizedBox(height: 16),
        Text('Crea tu negocio', style: tema.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Con estos datos los clientes te encontrarán. Luego podrás agregar logo, horario y productos.',
          style: tema.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        CampoValle(
          controller: _nombre,
          etiqueta: 'Nombre del negocio',
          icono: Icons.storefront_outlined,
          mayusculas: TextCapitalization.words,
          maxLongitud: 120,
        ),
        const SizedBox(height: 16),
        Text('Categoría', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cat in widget.categorias)
              ChoiceChip(
                avatar: Icon(cat.icono, size: 18, color: _categoria == cat.codigo ? Colors.white : c.textoSuave),
                label: Text(cat.descripcion),
                selected: _categoria == cat.codigo,
                showCheckmark: false,
                labelStyle: TextStyle(color: _categoria == cat.codigo ? Colors.white : c.texto, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _categoria = cat.codigo),
              ),
          ],
        ),
        const SizedBox(height: 16),
        CampoValle(
          controller: _descripcion,
          etiqueta: 'Descripción (opcional)',
          icono: Icons.notes_rounded,
          maxLongitud: 500,
          maxLineas: 3,
          mayusculas: TextCapitalization.sentences,
        ),
        const SizedBox(height: 24),
        BotonValle(texto: 'Crear mi negocio', icono: Icons.check_rounded, cargando: _guardando, onPressed: _crear),
      ],
    );
  }
}

/// Hoja para editar los datos del negocio y de entrega
class _FormularioNegocio extends StatefulWidget {
  const _FormularioNegocio({required this.negocio, required this.categorias});

  final Negocio negocio;
  final List<Categoria> categorias;

  @override
  State<_FormularioNegocio> createState() => _FormularioNegocioState();
}

class _FormularioNegocioState extends State<_FormularioNegocio> {
  late final _nombre = TextEditingController(text: widget.negocio.nombre);
  late final _descripcion = TextEditingController(text: widget.negocio.descripcion ?? '');
  late final _ruc = TextEditingController(text: widget.negocio.ruc ?? '');
  late final _minimo = TextEditingController(text: widget.negocio.pedidoMinimo.toStringAsFixed(2));
  late final _tiempo = TextEditingController(text: '${widget.negocio.tiempoPreparacion}');
  late final _radio = TextEditingController(text: widget.negocio.radioKm.toStringAsFixed(1));
  late String _categoria = widget.negocio.categoria.codigo;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nombre, _descripcion, _ruc, _minimo, _tiempo, _radio]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _dec(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim());

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    final minimo = _dec(_minimo);
    final tiempo = int.tryParse(_tiempo.text.trim());
    final radio = _dec(_radio);
    String? error;
    if (_nombre.text.trim().length < 2) error = 'Escribe el nombre del negocio';
    if (_ruc.text.trim().isNotEmpty && !RegExp(r'^\d{13}$').hasMatch(_ruc.text.trim())) error = 'El RUC debe tener 13 dígitos';
    if (minimo == null || minimo < 0) error = 'Pedido mínimo inválido';
    if (tiempo == null || tiempo < 5 || tiempo > 240) error = 'El tiempo de preparación va de 5 a 240 minutos';
    if (radio == null || radio <= 0 || radio > 50) error = 'El radio de entrega va hasta 50 km';
    if (error != null) return setState(() => _error = error);

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final n = await CatalogoService.actualizarNegocio({
        'nombre': _nombre.text.trim(),
        'descripcion': _descripcion.text.trim(),
        'categoria': _categoria,
        'ruc': _ruc.text.trim(),
        'pedidoMinimo': minimo,
        'tiempoPreparacion': tiempo,
        'radioKm': radio,
      });
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Datos del negocio', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            CampoValle(controller: _nombre, etiqueta: 'Nombre', icono: Icons.storefront_outlined, mayusculas: TextCapitalization.words, maxLongitud: 120),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.category_outlined)),
              items: [for (final c in widget.categorias) DropdownMenuItem(value: c.codigo, child: Text(c.descripcion))],
              onChanged: (v) => setState(() => _categoria = v ?? _categoria),
            ),
            const SizedBox(height: 12),
            CampoValle(
              controller: _descripcion,
              etiqueta: 'Descripción',
              icono: Icons.notes_rounded,
              maxLongitud: 500,
              maxLineas: 3,
              mayusculas: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            CampoValle(
              controller: _ruc,
              etiqueta: 'RUC (opcional)',
              icono: Icons.badge_outlined,
              tipoTeclado: TextInputType.number,
              formateadores: [FilteringTextInputFormatter.digitsOnly],
              maxLongitud: 13,
            ),
            const SizedBox(height: 20),
            Text('Entrega', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            // El envío ya no lo fija el negocio: lo calcula ValleXpress por distancia y es del repartidor
            const InsigniaValle(
              'El envío lo calcula ValleXpress según la distancia hasta el cliente y se lo lleva el repartidor',
              color: AppTheme.infoColor,
              icono: Icons.delivery_dining_outlined,
            ),
            const SizedBox(height: 12),
            CampoValle(
              controller: _minimo,
              etiqueta: 'Pedido mínimo \$',
              icono: Icons.shopping_bag_outlined,
              tipoTeclado: const TextInputType.numberWithOptions(decimal: true),
              formateadores: decimal,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CampoValle(
                    controller: _tiempo,
                    etiqueta: 'Preparación (min)',
                    icono: Icons.timer_outlined,
                    tipoTeclado: TextInputType.number,
                    formateadores: [FilteringTextInputFormatter.digitsOnly],
                    maxLongitud: 3,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CampoValle(
                    controller: _radio,
                    etiqueta: 'Radio (km)',
                    icono: Icons.radar_rounded,
                    tipoTeclado: const TextInputType.numberWithOptions(decimal: true),
                    formateadores: decimal,
                    accion: TextInputAction.done,
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.errorColor)),
              ),
            const SizedBox(height: 20),
            BotonValle(texto: 'Guardar', icono: Icons.check_rounded, cargando: _guardando, onPressed: _guardar),
          ],
        ),
      ),
    );
  }
}
