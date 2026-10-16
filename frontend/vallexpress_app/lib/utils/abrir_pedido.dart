import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/pedidos/pedido_detalle_screen.dart';
import '../screens/repartidor/entrega_screen.dart';
import '../screens/vendedor/pedido_negocio_screen.dart';

/// Abre un pedido en la pantalla de quien lo mira, con sus acciones: el vendedor en la de su negocio, el
/// repartidor en la de la entrega y el cliente en su seguimiento. Lo usan la lista de avisos y el toque en una
/// notificación del celular.
Future<void> abrirPedido(BuildContext context, int pedidoId) {
  final pantalla = switch (context.read<AuthProvider>().usuario?['tipoUsuario']) {
    'vendedor' => PedidoNegocioScreen(pedidoId: pedidoId),
    'repartidor' => EntregaScreen(pedidoId: pedidoId),
    _ => PedidoDetalleScreen(pedidoId: pedidoId),
  };
  return Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
}
