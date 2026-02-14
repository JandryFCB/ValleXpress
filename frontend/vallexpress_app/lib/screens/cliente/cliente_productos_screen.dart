import '../../config/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vallexpress_app/services/product_service.dart';
import 'package:vallexpress_app/services/pedido_service.dart';
import 'package:vallexpress_app/services/address_service.dart';
import '../profile/addresses_screen.dart';

class ClienteProductosScreen extends StatefulWidget {
  const ClienteProductosScreen({super.key});

  @override
  State<ClienteProductosScreen> createState() => _ClienteProductosScreenState();
}

class _ClienteProductosScreenState extends State<ClienteProductosScreen> {
  List<dynamic> productos = [];
  bool loading = true;
  Map<String, int> carrito = {}; // productId -> cantidad

  // Direcciones del cliente
  List<dynamic> _direcciones = [];
  Map<String, dynamic>? _direccionSeleccionada;
  bool _cargandoDirecciones = false;

  // Mapa para seleccionar nueva dirección
  final MapController _mapController = MapController();
  LatLng? _tempLocation;
  final TextEditingController _nombreDireccionController =
      TextEditingController();
  final TextEditingController _referenciaController = TextEditingController();
  bool _isSavingDireccion = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarDirecciones();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nombreDireccionController.dispose();
    _referenciaController.dispose();
    super.dispose();
  }

  /// Carga las direcciones guardadas del cliente
  Future<void> _cargarDirecciones() async {
    setState(() => _cargandoDirecciones = true);
    try {
      // Intentar obtener la predeterminada primero
      final predeterminada = await AddressService.predeterminada();

      // Cargar todas las direcciones
      final direcciones = await AddressService.listar();

      if (!mounted) return;

      setState(() {
        _direcciones = direcciones;
        // Seleccionar la predeterminada o la primera disponible
        _direccionSeleccionada =
            predeterminada ??
            (direcciones.isNotEmpty
                ? direcciones.first as Map<String, dynamic>
                : null);
        _cargandoDirecciones = false;
      });
    } catch (e) {
      debugPrint('Error cargando direcciones: $e');
      if (mounted) {
        setState(() => _cargandoDirecciones = false);
      }
    }
  }

  /// Abre el selector de direcciones con opción de agregar nueva
  void _mostrarSelectorDirecciones() {
    // Reset temp location
    _tempLocation = null;
    _nombreDireccionController.clear();
    _referenciaController.clear();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Seleccionar dirección de entrega',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Lista de direcciones existentes
                        if (_direcciones.isNotEmpty) ...[
                          Flexible(
                            child: ListView.builder(
                              controller: scrollController,
                              shrinkWrap: true,
                              itemCount: _direcciones.length,
                              itemBuilder: (context, index) {
                                final dir =
                                    _direcciones[index] as Map<String, dynamic>;
                                final isSelected =
                                    _direccionSeleccionada?['id'] == dir['id'];
                                final esPredeterminada =
                                    dir['esPredeterminada'] == true;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primaryColor.withOpacity(
                                            0.15,
                                          )
                                        : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primaryColor
                                          : Colors.white.withOpacity(0.1),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      setState(
                                        () => _direccionSeleccionada = dir,
                                      );
                                      Navigator.pop(context);
                                    },
                                    leading: Icon(
                                      esPredeterminada
                                          ? Icons.home
                                          : Icons.location_on,
                                      color: isSelected
                                          ? AppTheme.primaryColor
                                          : Colors.white70,
                                    ),
                                    title: Text(
                                      dir['nombre'] ?? 'Sin nombre',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${dir['direccion'] ?? ''}${dir['ciudad'] != null ? ', ${dir['ciudad']}' : ''}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 12,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: isSelected
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: AppTheme.primaryColor,
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Mensaje si no hay direcciones
                        if (_direcciones.isEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.location_off,
                                  color: Colors.orange,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No tienes direcciones guardadas',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ve a tu perfil para agregar una dirección primero',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Botón para gestionar direcciones existentes
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _irAGestionarDirecciones();
                            },
                            icon: const Icon(Icons.edit_location),
                            label: const Text('Gestionar mis direcciones'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.3),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Guarda una nueva dirección desde el mapa
  Future<void> _guardarNuevaDireccion(StateSetter setModalState) async {
    if (_tempLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Selecciona una ubicación en el mapa'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_nombreDireccionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ingresa un nombre para la dirección'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setModalState(() => _isSavingDireccion = true);

    try {
      final nuevaDireccion = await AddressService.crear(
        nombre: _nombreDireccionController.text.trim(),
        direccion: _referenciaController.text.trim().isNotEmpty
            ? _referenciaController.text.trim()
            : 'Ubicación seleccionada en mapa',
        latitud: _tempLocation!.latitude,
        longitud: _tempLocation!.longitude,
        esPredeterminada:
            _direcciones.isEmpty, // Primera dirección = predeterminada
      );

      if (!mounted) return;

      // Actualizar lista y seleccionar la nueva dirección
      await _cargarDirecciones();

      setState(() {
        _direccionSeleccionada = nuevaDireccion;
      });

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dirección guardada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setModalState(() => _isSavingDireccion = false);
      }
    }
  }

  /// Navega a la pantalla de gestión de direcciones
  void _irAGestionarDirecciones() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressesScreen()),
    ).then((_) => _cargarDirecciones()); // Recargar al volver
  }

  Map<String, List<dynamic>> _agruparPorTienda(List<dynamic> productos) {
    final map = <String, List<dynamic>>{};
    for (final p in productos) {
      final vendedor = p['vendedor'];
      final tienda = (vendedor?['nombreNegocio'] ?? 'Sin tienda').toString();
      map.putIfAbsent(tienda, () => []);
      map[tienda]!.add(p);
    }
    return map;
  }

  String? _getVendedorIdDeProducto(dynamic producto) {
    final vendedor = producto['vendedor'];
    if (vendedor is Map) {
      return vendedor['id']?.toString();
    }
    return null;
  }

  Future<void> _cargar() async {
    try {
      final data = await ProductService.listarProductosPublicos();
      if (!mounted) return;
      setState(() {
        productos = data;
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR CLIENTE PRODUCTOS: $e');
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _agregarAlCarrito(dynamic producto) {
    setState(() {
      final id = producto['id'].toString();
      carrito[id] = (carrito[id] ?? 0) + 1;
    });
  }

  void _removerDelCarrito(dynamic producto) {
    setState(() {
      final id = producto['id'].toString();
      if (carrito.containsKey(id) && carrito[id]! > 0) {
        carrito[id] = carrito[id]! - 1;
        if (carrito[id] == 0) {
          carrito.remove(id);
        }
      }
    });
  }

  Future<void> _hacerPedido() async {
    if (carrito.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Carrito vacío')));
      return;
    }

    // Validar que haya una dirección seleccionada
    if (_direccionSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Selecciona una dirección de entrega'),
          backgroundColor: Colors.orange,
        ),
      );
      _mostrarSelectorDirecciones();
      return;
    }

    // Agrupar productos por vendedor
    final productosPorVendedor = <String, List<Map<String, dynamic>>>{};

    for (final id in carrito.keys) {
      final producto = productos.firstWhere((p) => p['id'].toString() == id);
      final vendedorId = _getVendedorIdDeProducto(producto);

      if (vendedorId == null) continue;

      productosPorVendedor.putIfAbsent(vendedorId, () => []);
      productosPorVendedor[vendedorId]!.add({
        'productoId': id,
        'cantidad': carrito[id],
      });
    }

    // Crear pedido para cada vendedor
    try {
      final direccionId = _direccionSeleccionada!['id']?.toString();

      for (final vendedorId in productosPorVendedor.keys) {
        await PedidoService.crearPedido(
          vendedorId: vendedorId,
          productos: productosPorVendedor[vendedorId]!,
          metodoPago: 'efectivo',
          notasCliente: '',
          direccionEntregaId: direccionId, // 👈 Usar dirección seleccionada
        );
      }

      if (!mounted) return;

      setState(() => carrito.clear());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Pedidos creados exitosamente!')),
      );

      // Volver a pantalla anterior
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _badgeCantidad(int cantidad) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.35)),
      ),
      child: Text(
        'x$cantidad',
        style: const TextStyle(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _btnCircle(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  /// Widget para mostrar el selector de dirección en la barra inferior
  Widget _buildDireccionSelector() {
    if (_cargandoDirecciones) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryColor,
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Cargando dirección...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_direccionSeleccionada == null) {
      // Sin dirección configurada
      return InkWell(
        onTap: _mostrarSelectorDirecciones,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withOpacity(0.5)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text(
                'Seleccionar dirección',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: Colors.orange, size: 18),
            ],
          ),
        ),
      );
    }

    // Dirección seleccionada
    final nombre = _direccionSeleccionada!['nombre'] ?? 'Sin nombre';
    final direccion = _direccionSeleccionada!['direccion'] ?? '';
    final esPredeterminada =
        _direccionSeleccionada!['esPredeterminada'] == true;

    return InkWell(
      onTap: _mostrarSelectorDirecciones,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              esPredeterminada ? Icons.home : Icons.location_on,
              color: AppTheme.primaryColor,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    direccion,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              color: AppTheme.primaryColor,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _agruparPorTienda(productos);
    final tiendas = grupos.keys.toList();

    double totalGastado = 0.0;
    carrito.forEach((id, cantidad) {
      final producto = productos.firstWhere(
        (p) => p['id'].toString() == id,
        orElse: () => null,
      );
      if (producto != null && producto['precio'] != null) {
        totalGastado +=
            (double.tryParse(producto['precio'].toString()) ?? 0) * cantidad;
      }
    });
    final totalCarrito = carrito.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Productos'),
        elevation: 0,
        backgroundColor: const Color(0xFF0F2F3A),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                140,
              ), // Más espacio para la barra inferior
              itemCount: tiendas.length,
              itemBuilder: (_, i) {
                final tienda = tiendas[i];
                final items = grupos[tienda]!;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Título tienda
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          tienda,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Productos
                      ...items.map((p) {
                        final id = p['id'].toString();
                        final cantidad = carrito[id] ?? 0;
                        final disponible = (p['disponible'] == true);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F2F3A).withOpacity(0.60),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Icono izq
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.shopping_bag,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (p['nombre'] ?? 'Producto').toString(),
                                      style: TextStyle(
                                        color: disponible
                                            ? Colors.white
                                            : Colors.white38,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '\$${p['precio']}',
                                      style: TextStyle(
                                        color: disponible
                                            ? const Color(0xFF52FF7A)
                                            : Colors.white38,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '⏱ ${p['tiempoPreparacion'] ?? 0} min preparación',
                                      style: TextStyle(
                                        color: disponible
                                            ? AppTheme.primaryColor
                                            : Colors.white38,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (!disponible) ...[
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Producto no disponible',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                    if (cantidad > 0) ...[
                                      const SizedBox(height: 8),
                                      _badgeCantidad(cantidad),
                                    ],
                                  ],
                                ),
                              ),

                              // Botones + / -
                              Column(
                                children: [
                                  _btnCircle(
                                    Icons.add,
                                    disponible
                                        ? () => _agregarAlCarrito(p)
                                        : null,
                                  ),
                                  const SizedBox(height: 10),
                                  if (cantidad > 0)
                                    _btnCircle(
                                      Icons.remove,
                                      () => _removerDelCarrito(p),
                                    )
                                  else
                                    const SizedBox(height: 30),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),

      // Barra inferior con selector de dirección
      bottomNavigationBar: totalCarrito > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2F3A),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Selector de dirección
                    Row(
                      children: [
                        const Icon(
                          Icons.delivery_dining,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Entregar en:',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDireccionSelector()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Colors.white24),
                    const SizedBox(height: 12),
                    // Total y botón de pedido
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalCarrito producto${totalCarrito != 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total: \$${totalGastado.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF52FF7A),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _hacerPedido,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: AppTheme.backgroundColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            child: const Text(
                              'Pedir Ahora',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
