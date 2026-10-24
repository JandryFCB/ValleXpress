import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/producto.dart';
import '../../services/api_error.dart';
import '../../services/catalogo_service.dart';
import '../../utils/imagen.dart';
import '../../widgets/ui/ui.dart';

/// Crear o editar un producto: imagen, nombre, precio, descripción, sección, estado y stock.
/// Devuelve true al guardar o borrar (para que la lista se recargue).
class ProductoFormScreen extends StatefulWidget {
  const ProductoFormScreen({super.key, this.producto, this.secciones = const []});

  final Producto? producto;

  /// Secciones que ya existen en el menú (se sugieren al escribir)
  final List<String> secciones;

  @override
  State<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends State<ProductoFormScreen> {
  late final Producto? _p = widget.producto;
  late final _nombre = TextEditingController(text: _p?.nombre ?? '');
  late final _precio = TextEditingController(text: _p == null ? '' : _p.precio.toStringAsFixed(2));
  late final _descripcion = TextEditingController(text: _p?.descripcion ?? '');
  late final _seccion = TextEditingController(text: _p?.seccion ?? '');
  late final _stock = TextEditingController(text: '${_p?.stock ?? 0}');
  late EstadoProducto _estado = _p?.estado ?? EstadoProducto.disponible;
  late bool _controlaStock = _p?.controlaStock ?? false;
  String? _imagenNueva; // base64 de la imagen elegida (aún sin subir)
  bool _guardando = false;
  String? _error;

  bool get _editando => _p != null;

  @override
  void dispose() {
    for (final c in [_nombre, _precio, _descripcion, _seccion, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirImagen() async {
    final b64 = await elegirImagenBase64(context, titulo: 'Foto del producto');
    if (b64 != null && mounted) setState(() => _imagenNueva = b64);
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    final precio = double.tryParse(_precio.text.replaceAll(',', '.').trim());
    final stock = int.tryParse(_stock.text.trim());
    String? error;
    if (_nombre.text.trim().length < 2) error = 'Escribe el nombre del producto';
    if (precio == null || precio <= 0) error = 'Escribe un precio mayor que 0';
    if (_controlaStock && (stock == null || stock < 0)) error = 'El stock debe ser un número de 0 en adelante';
    if (error != null) return setState(() => _error = error);

    setState(() {
      _guardando = true;
      _error = null;
    });
    final datos = <String, dynamic>{
      'nombre': _nombre.text.trim(),
      'precio': precio,
      'descripcion': _descripcion.text.trim(),
      'seccion': _seccion.text.trim(),
      'estado': _estado.codigo,
      'controlaStock': _controlaStock,
    };
    try {
      if (!_editando) {
        await CatalogoService.crearProducto({...datos, if (_controlaStock) 'stock': stock, if (_imagenNueva != null) 'imagen': _imagenNueva});
      } else {
        await CatalogoService.actualizarProducto(_p!.id, datos);
        if (_controlaStock && stock != _p.stock) await CatalogoService.fijarStock(_p.id, stock!);
        if (_imagenNueva != null) await CatalogoService.subirImagenProducto(_p.id, _imagenNueva!);
      }
      if (!mounted) return;
      mostrarExito(context, _editando ? 'Producto actualizado' : 'Producto agregado');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar este producto?'),
        content: const Text('Dejará de aparecer en tu menú. Si solo quieres quitarlo por un tiempo, mejor márcalo como oculto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CatalogoService.eliminarProducto(_p!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    final escritorio = esEscritorio(context);
    final foto = GestureDetector(
      onTap: _elegirImagen,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_imagenNueva != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.memory(base64Decode(_imagenNueva!), fit: BoxFit.cover),
              )
            else if (_p?.imagen != null)
              ImagenRed(url: _p!.imagen, radio: 20)
            else
              Container(
                decoration: BoxDecoration(
                  color: c.tarjeta,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.borde),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 40, color: c.primario),
                    const SizedBox(height: 8),
                    Text('Agregar foto', style: tema.titleSmall?.copyWith(color: c.primario)),
                    Text('Una buena foto vende más', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                  ],
                ),
              ),
            if (_imagenNueva != null || _p?.imagen != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Cambiar',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final campos = <Widget>[
      CampoValle(controller: _nombre, etiqueta: 'Nombre', icono: Icons.fastfood_outlined, mayusculas: TextCapitalization.sentences, maxLongitud: 120),
      const SizedBox(height: 14),
      CampoValle(
        controller: _precio,
        etiqueta: 'Precio (\$)',
        icono: Icons.attach_money_rounded,
        tipoTeclado: const TextInputType.numberWithOptions(decimal: true),
        formateadores: decimal,
        maxLongitud: 8,
      ),
      const SizedBox(height: 14),
      CampoValle(
        controller: _descripcion,
        etiqueta: 'Descripción (opcional)',
        icono: Icons.notes_rounded,
        mayusculas: TextCapitalization.sentences,
        maxLongitud: 500,
        maxLineas: 3,
      ),
      const SizedBox(height: 14),
      // Sección: se escribe o se toca una de las que ya existen (chips, porque una lista
      // desplegable debajo del campo queda tapada por el teclado en el móvil)
      CampoValle(
        controller: _seccion,
        etiqueta: 'Sección del menú (opcional)',
        icono: Icons.view_list_outlined,
        mayusculas: TextCapitalization.sentences,
        maxLongitud: 60,
        ayuda: widget.secciones.isEmpty ? 'Ej: Pizzas, Bebidas, Postres' : null,
        onChanged: (_) => setState(() {}),
      ),
      if (widget.secciones.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final s in widget.secciones)
              ChoiceChip(label: Text(s), selected: _seccion.text.trim().toLowerCase() == s.toLowerCase(), onSelected: (_) => setState(() => _seccion.text = s)),
          ],
        ),
      ],
      const SizedBox(height: 24),
      Text('Estado', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<EstadoProducto>(
          showSelectedIcon: false,
          // Sin íconos: con ellos "Disponible" no cabe en pantallas angostas y se parte en dos líneas
          segments: [for (final e in EstadoProducto.values) ButtonSegment(value: e, label: Text(e.etiqueta, maxLines: 1))],
          selected: {_estado},
          onSelectionChanged: (s) => setState(() => _estado = s.first),
        ),
      ),
      const SizedBox(height: 6),
      Text(switch (_estado) {
        EstadoProducto.disponible => 'Los clientes lo ven y lo pueden pedir.',
        EstadoProducto.agotado => 'Los clientes lo ven, pero no lo pueden pedir.',
        EstadoProducto.oculto => 'Los clientes no lo ven.',
      }, style: tema.bodySmall?.copyWith(color: c.textoSuave)),
      const SizedBox(height: 16),
      TarjetaValle(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Controlar stock'),
              subtitle: const Text('Se agota solo cuando llega a 0'),
              value: _controlaStock,
              onChanged: (v) => setState(() => _controlaStock = v),
            ),
            if (_controlaStock)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 0, 12),
                child: CampoValle(
                  controller: _stock,
                  etiqueta: 'Unidades disponibles',
                  icono: Icons.inventory_2_outlined,
                  tipoTeclado: TextInputType.number,
                  formateadores: [FilteringTextInputFormatter.digitsOnly],
                  maxLongitud: 6,
                  accion: TextInputAction.done,
                ),
              ),
          ],
        ),
      ),
    ];

    return FondoValle(
      titulo: _editando ? 'Editar producto' : 'Nuevo producto',
      anchoEscritorio: 1000,
      acciones: [if (_editando) IconButton(onPressed: _eliminar, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', color: AppTheme.errorColor)],
      barraInferior: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: escritorio
              ? null
              : BoxDecoration(
                  color: c.tarjeta,
                  border: Border(top: BorderSide(color: c.borde)),
                ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: tema.bodySmall?.copyWith(color: AppTheme.errorColor)),
                ),
              BotonValle(texto: _editando ? 'Guardar cambios' : 'Agregar producto', icono: Icons.check_rounded, cargando: _guardando, onPressed: _guardar),
            ],
          ),
        ),
      ),
      child: escritorio
          // Computador: la foto a la izquierda y los datos a la derecha
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 380, child: foto),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: campos),
                  ),
                ],
              ),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [foto, const SizedBox(height: 20), ...campos]),
    );
  }
}
