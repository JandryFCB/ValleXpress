import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/direccion.dart';
import '../../services/address_service.dart';
import '../../services/api_error.dart';
import '../../widgets/ui/ui.dart';
import 'address_picker_screen.dart';

/// Mis direcciones: lista con la predeterminada primero. Agregar, editar, marcar predeterminada y borrar.
class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  bool _cargando = true;
  String? _error;
  List<Direccion> _direcciones = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _direcciones.isEmpty; // si ya hay datos, se refrescan sin parpadeo
      _error = null;
    });
    try {
      final lista = await AddressService.listar();
      if (!mounted) return;
      setState(() {
        _direcciones = lista.map((d) => Direccion.desdeJson(d as Map<String, dynamic>)).toList();
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

  Future<void> _agregarOEditar([Direccion? actual]) async {
    final elegida = await Navigator.push<DireccionElegida>(
      context,
      MaterialPageRoute(builder: (_) => AddressPickerScreen(actual: actual), settings: RouteSettings(name: actual == null ? 'nueva' : 'editar')),
    );
    if (elegida == null || !mounted) return;

    try {
      if (actual == null) {
        await AddressService.crear(
          nombre: elegida.nombre,
          direccion: elegida.direccion,
          latitud: elegida.latitud,
          longitud: elegida.longitud,
          esPredeterminada: elegida.esPredeterminada || _direcciones.isEmpty, // la primera siempre queda predeterminada
          tipo: elegida.tipo.codigo,
          referencia: elegida.referencia,
          instrucciones: elegida.instrucciones,
        );
      } else {
        await AddressService.actualizar(
          actual.id,
          // se envía vacío (no null) para poder BORRAR el nombre, la referencia o las indicaciones
          nombre: elegida.nombre ?? '',
          direccion: elegida.direccion,
          latitud: elegida.latitud,
          longitud: elegida.longitud,
          esPredeterminada: elegida.esPredeterminada,
          tipo: elegida.tipo.codigo,
          referencia: elegida.referencia ?? '',
          instrucciones: elegida.instrucciones ?? '',
        );
      }
      if (!mounted) return;
      mostrarExito(context, actual == null ? 'Dirección guardada' : 'Dirección actualizada');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _marcarPredeterminada(Direccion d) async {
    try {
      await AddressService.marcarPredeterminada(d.id);
      if (!mounted) return;
      mostrarExito(context, '"${d.titulo}" es ahora tu dirección predeterminada');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  Future<void> _eliminar(Direccion d) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar esta dirección?'),
        content: Text('Se eliminará "${d.titulo}". Tus pedidos anteriores no se ven afectados.'),
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
    if (confirmado != true) return;

    try {
      await AddressService.eliminar(d.id);
      if (!mounted) return;
      mostrarMensaje(context, 'Dirección eliminada');
      await _cargar();
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FondoValle(
      titulo: 'Mis direcciones',
      botonFlotante: (_cargando || _error != null || _direcciones.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _agregarOEditar(),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Agregar'),
            ),
      child: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando) return const EsqueletoLista(cantidad: 3);

    if (_error != null) {
      return EstadoVacio(
        icono: Icons.cloud_off_rounded,
        color: AppTheme.errorColor,
        titulo: 'No pudimos cargar tus direcciones',
        mensaje: _error,
        textoAccion: 'Reintentar',
        onAccion: _cargar,
      );
    }

    if (_direcciones.isEmpty) {
      return EstadoVacio(
        icono: Icons.wrong_location_outlined,
        titulo: 'Aún no tienes direcciones',
        mensaje: 'Agrega una para que tus pedidos lleguen directo a tu puerta.',
        textoAccion: 'Agregar mi primera dirección',
        onAccion: () => _agregarOEditar(),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), // espacio para que el botón flotante no tape la última tarjeta
        itemCount: _direcciones.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final d = _direcciones[i];
          return _TarjetaDireccion(
            direccion: d,
            onEditar: () => _agregarOEditar(d),
            onPredeterminada: () => _marcarPredeterminada(d),
            onEliminar: () => _eliminar(d),
          );
        },
      ),
    );
  }
}

class _TarjetaDireccion extends StatelessWidget {
  const _TarjetaDireccion({required this.direccion, required this.onEditar, required this.onPredeterminada, required this.onEliminar});

  final Direccion direccion;
  final VoidCallback onEditar;
  final VoidCallback onPredeterminada;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    final tema = Theme.of(context).textTheme;
    final d = direccion;

    return TarjetaValle(
      onTap: onEditar,
      colorBorde: d.esPredeterminada ? c.primario : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.primario.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(d.tipo.icono, color: c.primario),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(d.titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    if (d.esPredeterminada) InsigniaValle('Predeterminada', color: c.primario, icono: Icons.star_rounded),
                  ],
                ),
                const SizedBox(height: 4),
                Text(d.direccion, style: tema.bodyMedium?.copyWith(color: c.texto), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (d.referencia != null) ...[
                  const SizedBox(height: 2),
                  Text(d.referencia!, style: tema.bodySmall?.copyWith(color: c.textoSuave), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: Icon(Icons.more_vert_rounded, color: c.textoSuave),
            onSelected: (v) {
              switch (v) {
                case 'editar':
                  onEditar();
                case 'predeterminada':
                  onPredeterminada();
                case 'eliminar':
                  onEliminar();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'editar', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'), contentPadding: EdgeInsets.zero)),
              if (!d.esPredeterminada)
                const PopupMenuItem(value: 'predeterminada', child: ListTile(leading: Icon(Icons.star_outline_rounded), title: Text('Usar como predeterminada'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                value: 'eliminar',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                  title: Text('Eliminar', style: TextStyle(color: AppTheme.errorColor)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
