import 'package:flutter/services.dart';
import 'sonido_web.dart' if (dart.library.io) 'sonido_movil.dart' as plataforma;

/// Aviso sonoro de "pedido nuevo". En el celular, el sonido de alerta del sistema; en el navegador (donde ese no
/// suena) un "ding-ding" con el audio del navegador, para el negocio que atiende desde el computador.
void sonarPedidoNuevo() {
  SystemSound.play(SystemSoundType.alert);
  plataforma.ding();
}
