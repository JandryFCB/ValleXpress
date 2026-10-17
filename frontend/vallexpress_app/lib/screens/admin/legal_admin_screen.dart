import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/legal.dart';
import '../../services/admin_service.dart';
import '../../services/api_error.dart';
import '../../services/legal_service.dart';
import '../../widgets/ui/ui.dart';
import '../legal/documento_legal_screen.dart';

/// Términos y privacidad para el administrador: la versión vigente de cada documento, cuántas cuentas ya la
/// aceptaron y los enlaces web que se publican en Google Play. Los textos se editan en backend/legal/*.md: al
/// subir su "version", a cada usuario se le pide aceptarlos otra vez al entrar.
class LegalAdminScreen extends StatefulWidget {
  const LegalAdminScreen({super.key});

  @override
  State<LegalAdminScreen> createState() => _LegalAdminScreenState();
}

class _LegalAdminScreenState extends State<LegalAdminScreen> {
  List<({DocumentoLegal documento, int cuentas, int aceptaron})>? _docs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final d = await AdminService.legal();
      if (mounted) setState(() => (_docs = d, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = textoDeError(e));
    }
  }

  void _copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    HapticFeedback.selectionClick();
    mostrarMensaje(context, 'Enlace copiado');
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final docs = _docs;
    return FondoValle(
      appBar: AppBar(title: const Text('Términos y privacidad')),
      child: docs == null
          ? (_error != null
              ? EstadoVacio(icono: Icons.cloud_off_rounded, color: AppTheme.errorColor, titulo: 'No pudimos cargar los documentos', mensaje: _error, textoAccion: 'Reintentar', onAccion: _cargar)
              : const EsqueletoLista(cantidad: 4, conImagen: false))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  for (final (i, d) in docs.indexed)
                    Aparecer(
                      indice: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TarjetaValle(
                          onTap: () => abrirDocumentoLegal(context, d.documento.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(d.documento.esPrivacidad ? Icons.privacy_tip_rounded : Icons.description_rounded, color: c.primario),
                                const SizedBox(width: 10),
                                Expanded(child: Text(d.documento.titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                                const Icon(Icons.chevron_right_rounded),
                              ]),
                              const SizedBox(height: 6),
                              Text('Versión ${d.documento.version} · vigente desde el ${fechaLegal(d.documento.vigencia)}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(value: d.cuentas == 0 ? 0 : d.aceptaron / d.cuentas, minHeight: 8, backgroundColor: c.borde),
                              ),
                              const SizedBox(height: 6),
                              Text('${d.aceptaron} de ${d.cuentas} ${d.cuentas == 1 ? 'cuenta activa aceptó' : 'cuentas activas aceptaron'} esta versión', style: tema.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const EncabezadoSeccion('Enlaces para Google Play', subtitulo: 'Páginas públicas con el mismo texto'),
                  TarjetaValle(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (titulo, id) in const [('Política de privacidad', 'privacidad'), ('Eliminar cuenta', 'eliminar-cuenta'), ('Todos los documentos', '')])
                          ListTile(
                            title: Text(titulo),
                            subtitle: Text(LegalService.urlWeb(id).replaceAll(RegExp(r'/$'), ''), style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                            trailing: const Icon(Icons.copy_rounded),
                            onTap: () => _copiar(LegalService.urlWeb(id).replaceAll(RegExp(r'/$'), '')),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Para cambiar un texto se edita su archivo en el servidor (backend/legal) y se sube su versión: a cada usuario se le pedirá aceptarlo de nuevo al entrar.',
                    style: tema.bodySmall?.copyWith(color: c.textoSuave),
                  ),
                ],
              ),
            ),
    );
  }
}
