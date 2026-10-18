import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/reputacion.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../widgets/ui/ui.dart';
import '../repartidor/reputacion_screen.dart';
import 'pedir_motivo.dart';

/// Reputación de un repartidor para el administrador: qué dicen clientes y negocios (con quién lo dijo) y sus
/// advertencias. Desde aquí se le envía una advertencia (le llega por notificación y correo).
class ReputacionAdminScreen extends StatefulWidget {
  const ReputacionAdminScreen({super.key, required this.usuario, required this.nombre});

  final String usuario;
  final String nombre;

  @override
  State<ReputacionAdminScreen> createState() => _ReputacionAdminScreenState();
}

class _ReputacionAdminScreenState extends State<ReputacionAdminScreen> {
  Reputacion? _r;
  String? _error;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await AdminService.reputacionRepartidor(widget.usuario);
      if (mounted) setState(() => (_r = r, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  Future<void> _advertir() async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Advertir a ${widget.nombre}',
      explicacion: 'Le llega por notificación y por correo, con el aviso de que si no mejora su cuenta será suspendida o dada de baja.',
      textoBoton: 'Enviar advertencia',
      minimo: 10,
      sugerencias: const [
        'Recibimos quejas por llegar tarde a las entregas',
        'Un cliente reportó un trato irrespetuoso',
        'Un negocio reportó que no recogiste un pedido aceptado',
        'Reportaron que el pedido llegó en mal estado',
      ],
    );
    if (motivo == null) return;
    setState(() => _enviando = true);
    try {
      final r = await AdminService.advertirRepartidor(widget.usuario, motivo);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _r = r);
      mostrarExito(context, 'Advertencia enviada');
    } catch (e) {
      if (mounted) mostrarError(context, textoDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => FondoValle(
        appBar: AppBar(title: Text(widget.nombre)),
        barraInferior: _r == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: BotonValle(texto: 'Enviar una advertencia', icono: Icons.warning_amber_rounded, tipo: TipoBoton.peligro, cargando: _enviando, onPressed: _advertir),
                ),
              ),
        child: _r == null
            ? (_error != null
                ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar la reputación', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
                : const EsqueletoLista(cantidad: 3, conImagen: false))
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [ReputacionVista(r: _r!, paraAdmin: true)]),
              ),
      );
}
