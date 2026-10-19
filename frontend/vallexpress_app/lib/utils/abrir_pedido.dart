import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/sugerencias_admin_screen.dart';
import '../screens/admin/suscripciones_admin_screen.dart';
import '../screens/profile/ayudanos_screen.dart';
import '../screens/pedidos/pedido_detalle_screen.dart';
import '../screens/repartidor/entrega_screen.dart';
import '../screens/repartidor/reputacion_screen.dart';
import '../screens/suscripcion/mi_suscripcion_screen.dart';
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

/// Abre lo que corresponde a un aviso: su pedido o, en los de cobros, la de la suscripción (Suscripciones
/// para el administrador, Mi suscripción para el vendedor o repartidor). Si el aviso no lleva a ningún lado no hace nada.
Future<void> abrirAviso(BuildContext context, {String? tipo, int? pedidoId}) async {
  if (pedidoId != null) return abrirPedido(context, pedidoId);
  final Widget? pantalla = switch (tipo) {
    'comprobante_nuevo' => const SuscripcionesAdminScreen(),
    'suscripcion_pagada' || 'comprobante_rechazado' => const MiSuscripcionScreen(),
    'advertencia_repartidor' => const MiReputacionScreen(),
    'sugerencia_nueva' => const SugerenciasAdminScreen(),
    'sugerencia_respondida' => const AyudanosScreen(),
    _ => null,
  };
  if (pantalla != null) await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
}
