import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/pedido_service.dart';

class ClienteMisPedidosScreen extends StatefulWidget {
  const ClienteMisPedidosScreen({super.key});

  // 🚀 CACHE: Almacenar pedidos en memoria para carga instantánea
  // NOTA: Públicas para que RastrearPedidoScreen pueda acceder a la misma caché
  static List<dynamic>? cachePedidos;
  static DateTime? lastFetch;
  static const Duration cacheDuration = Duration(minutes: 2);

  @override
  State<ClienteMisPedidosScreen> createState() =>
      _ClienteMisPedidosScreenState();
}

class _ClienteMisPedidosScreenState extends State<ClienteMisPedidosScreen> {
  List<dynamic> pedidos = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    // 🚀 Mostrar cache inmediatamente si existe y es fresco
    if (ClienteMisPedidosScreen.cachePedidos != null &&
        ClienteMisPedidosScreen.lastFetch != null) {
      final cacheAge = DateTime.now().difference(
        ClienteMisPedidosScreen.lastFetch!,
      );
      if (cacheAge < ClienteMisPedidosScreen.cacheDuration) {
        // Cache fresco: mostrar inmediatamente
        setState(() {
          pedidos = ClienteMisPedidosScreen.cachePedidos!;
          loading = false;
        });

        // Refrescar en background silenciosamente
        _refrescarSilencioso();
        return;
      }
    }

    // Sin cache o expirado: cargar normal
    await _cargarDesdeApi();
  }

  Future<void> _cargarDesdeApi() async {
    try {
      final data = await PedidoService.misPedidos();
      if (!mounted) return;

      // 🚀 Guardar en cache
      ClienteMisPedidosScreen.cachePedidos = data;
      ClienteMisPedidosScreen.lastFetch = DateTime.now();

      setState(() {
        pedidos = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Refresca en background sin mostrar loading
  Future<void> _refrescarSilencioso() async {
    try {
      final data = await PedidoService.misPedidos();
      if (!mounted) return;

      // Actualizar cache y UI solo si hay cambios
      if (data.length != pedidos.length ||
          (data.isNotEmpty &&
              pedidos.isNotEmpty &&
              data.first['id'] != pedidos.first['id'])) {
        ClienteMisPedidosScreen.cachePedidos = data;
        ClienteMisPedidosScreen.lastFetch = DateTime.now();
        setState(() => pedidos = data);
      }
    } catch (_) {
      // Silenciar errores de refresh background
    }
  }

  String _getEstadoTexto(String estado) {
    final mapa = {
      'pendiente': 'Pendiente',
      'confirmado': 'Confirmado',
      'preparando': 'Preparando',
      'listo': 'Listo',
      'en_camino': 'En camino',
      'entregado': 'Entregado',
      'recibido_cliente': 'Recibido',
      'cancelado': 'Cancelado',
    };
    return mapa[estado] ?? estado.replaceAll('_', ' ');
  }

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'pendiente':
        return const Color(0xFF8E9AAF);
      case 'confirmado':
        return AppTheme.clienteColor;
      case 'preparando':
        return const Color(0xFFFFA500);
      case 'listo':
        return const Color(0xFF2E7D32);
      case 'en_camino':
        return AppTheme.repartidorColor;
      case 'entregado':
      case 'recibido_cliente':
        return const Color(0xFF2E7D32);
      case 'cancelado':
        return const Color(0xFFD32F2F);
      default:
        return Colors.grey;
    }
  }

  String _fechaHoy() {
    final now = DateTime.now();
    const meses = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${now.day.toString().padLeft(2, '0')} ${meses[now.month - 1]} ${now.year}';
  }

  Widget _filaTotal(String label, dynamic value, {bool bold = false}) {
    final v = (value is num)
        ? value.toDouble()
        : double.tryParse(value.toString()) ?? 0.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        Text(
          '\$${v.toStringAsFixed(2)}',
          style: TextStyle(
            color: Colors.white,
            fontSize: bold ? 16 : 14,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _mostrarDetallePedido(dynamic p) {
    final vendedor = p['vendedor'];
    final detalles = (p['detalles'] as List?) ?? [];
    final estado = (p['estado'] ?? 'pendiente').toString();
    final tienda = (vendedor?['nombreNegocio'] ?? 'Sin tienda').toString();

    final double subtotal =
        double.tryParse(p['subtotal']?.toString() ?? '') ?? 0.0;
    final double costoDelivery =
        double.tryParse(p['costoDelivery']?.toString() ?? '') ?? 0.0;
    final double total = subtotal + costoDelivery;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: AppTheme.clienteColor.withOpacity(0.3),
              width: 2,
            ),
          ),

          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER (3 filas) + badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  AppTheme.clienteColor,
                                  AppTheme.accentColor,
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'Pedido',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),
                            Text(
                              'Tienda: $tienda',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '#${p['numeroPedido'] ?? ''}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _getEstadoColor(estado),
                              _getEstadoColor(estado).withOpacity(0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _getEstadoColor(estado).withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          _getEstadoTexto(estado),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12),

                  const Text(
                    'Productos',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (detalles.isEmpty)
                    Text(
                      'Sin productos',
                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                    )
                  else
                    ...detalles.map((d) {
                      final producto = d['producto'];
                      final nombre = (producto?['nombre'] ?? 'Producto')
                          .toString();
                      final cantidad = (d['cantidad'] ?? 0).toString();
                      final precioU = d['precioUnitario']?.toString() ?? '0.00';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shopping_bag,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$nombre  x$cantidad',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ),
                            Text(
                              '\$$precioU',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  const Divider(color: Colors.white12),
                  const SizedBox(height: 10),

                  _filaTotal('Subtotal', subtotal),
                  _filaTotal('Delivery', costoDelivery),
                  const SizedBox(height: 6),
                  _filaTotal('Total', total, bold: true),

                  const SizedBox(height: 14),

                  if (estado == 'pendiente')
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFD32F2F),
                            const Color(0xFFFF5252),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD32F2F).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            await PedidoService.cancelarPedido(p['id']);
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Pedido cancelado')),
                            );
                            _cargar();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '✕ Cancelar pedido',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),

                  if (estado == 'entregado')
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF2E7D32),
                            const Color(0xFF4CAF50),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2E7D32).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            await PedidoService.marcarRecibidoCliente(p['id']);
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('¡Pedido marcado como recibido!'),
                              ),
                            );
                            _cargar();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '✓ Marcar como recibido',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.cardColor,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.clienteColor.withOpacity(0.3),
                AppTheme.cardColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppTheme.clienteColor, AppTheme.accentColor],
          ).createShader(bounds),
          child: const Text(
            'Mis Pedidos',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 20,
            ),
          ),
        ),

        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.clienteColor.withOpacity(0.2),
                  AppTheme.clienteColor.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.clienteColor.withOpacity(0.3)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: AppTheme.clienteColor),
              tooltip: 'Actualizar',
              onPressed: _cargar,
            ),
          ),
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : pedidos.isEmpty
          ? const Center(child: Text('No tienes pedidos aún'))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.builder(
                itemCount: pedidos.length,
                itemBuilder: (_, i) {
                  final p = pedidos[i];
                  final vendedor = p['vendedor'];
                  final estado = (p['estado'] ?? 'pendiente').toString();
                  final tienda = (vendedor?['nombreNegocio'] ?? 'Sin tienda')
                      .toString();

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _mostrarDetallePedido(p),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.cardColor,
                              AppTheme.cardColor.withOpacity(0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _getEstadoColor(estado).withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _getEstadoColor(estado).withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header con pedido y badge
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.clienteColor.withOpacity(
                                      0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    color: AppTheme.clienteColor,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pedido #${p['numeroPedido']}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        tienda,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        _getEstadoColor(estado),
                                        _getEstadoColor(
                                          estado,
                                        ).withOpacity(0.8),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _getEstadoColor(
                                          estado,
                                        ).withOpacity(0.4),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    _getEstadoTexto(estado),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Total
                            Row(
                              children: [
                                Icon(
                                  Icons.attach_money,
                                  color: Colors.amber,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '\$${p['total'] ?? '0.00'}',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
