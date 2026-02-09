import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/repartidor_pedidos_service.dart';
import '../../services/repartidor_tracking_service.dart';

class RepartidorPedidosScreen extends StatefulWidget {
  const RepartidorPedidosScreen({super.key});

  @override
  State<RepartidorPedidosScreen> createState() =>
      _RepartidorPedidosScreenState();
}

class _RepartidorPedidosScreenState extends State<RepartidorPedidosScreen> {
  List<dynamic> pedidosAsignados = [];
  List<dynamic> pedidosPendientes = [];
  List<dynamic> pedidosVista = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final asignados = await RepartidorPedidosService.obtenerPedidos();
      final pendientes =
          await RepartidorPedidosService.obtenerPedidosPendientes();
      final vista = await RepartidorPedidosService.obtenerPedidosVista();
      if (!mounted) return;
      setState(() {
        pedidosAsignados = asignados;
        pedidosPendientes = pendientes;
        pedidosVista = vista;
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
        return AppTheme.repartidorColor;
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

  Future<void> _cambiarEstado(dynamic pedido, String nuevoEstado) async {
    try {
      await RepartidorPedidosService.cambiarEstado(pedido['id'], nuevoEstado);

      // Iniciar/Detener tracking según estado
      if (nuevoEstado == 'en_camino') {
        await RepartidorTrackingService.instance.start(context, pedido['id']);
      } else if (nuevoEstado == 'entregado') {
        await RepartidorTrackingService.instance.stop();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido marcado como $nuevoEstado')),
      );

      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // =========================
  // UI helpers
  // =========================
  static const _bg = Color(0xFF0A2A3A);
  static const _card = Color(0xFF133B4F);

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
    return '${now.day.toString().padLeft(2, '0')} '
        '${meses[now.month - 1]} '
        '${now.year}';
  }

  String _money(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '0') ?? 0.0;
    return d.toStringAsFixed(2);
  }

  // =========================
  // Dialog: Detalle
  // =========================
  void _mostrarDetallesPedido(dynamic pedido, String tipo) {
    final estado = (pedido['estado'] ?? '').toString();
    final numeroPedido =
        (pedido['numeroPedido'] ?? pedido['numero_pedido'] ?? pedido['id'])
            ?.toString() ??
        '';
    final total = pedido['total'];
    final subtotal = pedido['subtotal'];
    final delivery = pedido['costoDelivery'];
    final direccion = pedido['direccion_entrega']?.toString();
    final notas = pedido['notas']?.toString();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: AppTheme.repartidorColor.withOpacity(0.3),
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
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  AppTheme.repartidorColor,
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
                              '#$numeroPedido',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
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

                  // Info básica
                  Text(
                    'Total: \$${_money(total)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  if (tipo == 'asignados') ...[
                    const SizedBox(height: 8),
                    Text(
                      'Subtotal: \$${_money(subtotal)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Delivery: \$${_money(delivery)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],

                  if (direccion != null && direccion.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Dirección: $direccion',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],

                  if (notas != null && notas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Notas: $notas',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ✅ Acciones según TAB
                  if (tipo == 'pendientes') ...[
                    // Verificar si ya tiene pedido activo
                    if (_tienePedidoActivo()) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ya tienes un pedido activo. Completa el pedido asignado antes de aceptar otro.',
                                style: TextStyle(
                                  color: Colors.orange.shade300,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.repartidorColor,
                              const Color(0xFFFFA500),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.repartidorColor.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _aceptarPedido(pedido);
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
                            '✓ Aceptar pedido',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ] else if (tipo == 'asignados') ...[
                    if (estado == 'listo') ...[
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.repartidorColor,
                              const Color(0xFFFFA500),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.repartidorColor.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _cambiarEstado(pedido, 'en_camino');
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
                            '🚚 Marcar en camino',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (estado == 'en_camino') ...[
                      // Botón para iniciar/reenviar tracking de ubicación
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.grey.shade200],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              final running =
                                  RepartidorTrackingService.instance.running;
                              if (running) {
                                await RepartidorTrackingService.instance.stop();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tracking detenido'),
                                  ),
                                );
                                setState(() {});
                              } else {
                                Navigator.pop(context);
                                await RepartidorTrackingService.instance.start(
                                  context,
                                  pedido['id'],
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Tracking de ubicación activo',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: const Color(0xFF0B1F26),
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            RepartidorTrackingService.instance.running
                                ? '⏹ Detener tracking'
                                : '📍 Iniciar tracking',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // Cerrar
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

  // =========================
  // Verificar si tiene pedido activo
  // =========================
  bool _tienePedidoActivo() {
    final estadosActivos = [
      'confirmado',
      'preparando',
      'listo',
      'en_camino',
      'recogido',
    ];
    return pedidosAsignados.any((p) {
      final estado = (p['estado'] ?? '').toString();
      return estadosActivos.contains(estado);
    });
  }

  // =========================
  // Dialog: Aceptar pedido (costo delivery)
  // =========================
  Future<void> _aceptarPedido(dynamic pedido) async {
    // Validar que no tenga pedido activo
    if (_tienePedidoActivo()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Ya tienes un pedido asignado. Debes completarlo antes de aceptar otro.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final costoController = TextEditingController();

    final result = await showDialog<double>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: AppTheme.repartidorColor.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppTheme.repartidorColor, AppTheme.accentColor],
                  ).createShader(bounds),
                  child: const Text(
                    'Aceptar pedido',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: costoController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Costo de delivery',
                    prefixText: '\$ ',
                    filled: true,
                    fillColor: _card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.repartidorColor,
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.repartidorColor.withOpacity(0.55),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.repartidorColor,
                        width: 1.8,
                      ),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.3),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.repartidorColor,
                              const Color(0xFFFFA500),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.repartidorColor.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            final costo = double.tryParse(
                              costoController.text.trim().replaceAll(',', '.'),
                            );
                            if (costo != null && costo >= 0) {
                              Navigator.pop(context, costo);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Aceptar',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;

    try {
      await RepartidorPedidosService.aceptarPedido(pedido['id'], result);
      // Activar tracking automáticamente al aceptar
      await RepartidorTrackingService.instance.start(context, pedido['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido aceptado. Tracking activado')),
      );
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // =========================
  // Lista UI bonita
  // =========================
  Widget _buildPedidosList(List<dynamic> pedidos, String tipo) {
    if (pedidos.isEmpty) {
      return const Center(
        child: Text('No hay pedidos', style: TextStyle(color: Colors.white70)),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: pedidos.length,
        itemBuilder: (_, i) {
          final pedido = pedidos[i];
          final estado = (pedido['estado'] ?? '').toString();

          // ✅ usar numeroPedido (fallback por seguridad)
          final numeroPedido =
              (pedido['numeroPedido'] ??
                      pedido['numero_pedido'] ??
                      pedido['id'])
                  .toString();

          // total mostrado
          final total = (tipo == 'asignados')
              ? ((double.tryParse(pedido['subtotal']?.toString() ?? '0') ?? 0) +
                    (double.tryParse(
                          pedido['costoDelivery']?.toString() ?? '0',
                        ) ??
                        0))
              : (double.tryParse(pedido['total']?.toString() ?? '0') ?? 0);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _mostrarDetallesPedido(pedido, tipo),
              child: Container(
                padding: const EdgeInsets.all(14),
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
                            color: AppTheme.repartidorColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.delivery_dining_outlined,
                            color: AppTheme.repartidorColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pedido #$numeroPedido',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getEstadoTexto(estado),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _getEstadoColor(estado),
                                _getEstadoColor(estado).withOpacity(0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _getEstadoColor(estado).withOpacity(0.5),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Total
                    Row(
                      children: [
                        Icon(Icons.attach_money, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
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
                AppTheme.repartidorColor.withOpacity(0.3),
                AppTheme.cardColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppTheme.repartidorColor, AppTheme.accentColor],
          ).createShader(bounds),
          child: const Text(
            'Pedidos',
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
                  AppTheme.repartidorColor.withOpacity(0.2),
                  AppTheme.repartidorColor.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.repartidorColor.withOpacity(0.3),
              ),
            ),
            child: IconButton(
              onPressed: _cargar,
              icon: Icon(Icons.refresh, color: AppTheme.repartidorColor),
              tooltip: 'Actualizar',
            ),
          ),
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    indicatorColor: AppTheme.repartidorColor,
                    labelColor: AppTheme.repartidorColor,
                    unselectedLabelColor: Colors.white70,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.new_releases_outlined),
                        text: 'Nuevas',
                      ),
                      Tab(
                        icon: Icon(Icons.list_alt_outlined),
                        text: 'Disponibles',
                      ),
                      Tab(icon: Icon(Icons.delivery_dining), text: 'Asignados'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPedidosList(pedidosPendientes, 'pendientes'),
                        _buildPedidosList(pedidosVista, 'disponibles'),
                        _buildPedidosList(pedidosAsignados, 'asignados'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
