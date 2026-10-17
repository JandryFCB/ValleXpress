import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/legal.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_error.dart';
import '../../services/legal_service.dart';
import '../../widgets/ui/ui.dart';
import 'documento_legal_screen.dart';

/// Se muestra al entrar cuando hay una versión nueva de los términos o de la política de privacidad (o la cuenta la
/// creó el administrador y nunca los aceptó). Para seguir usando la app hay que aceptarlos; si no, puede cerrar
/// sesión (o eliminar su cuenta desde el perfil).
class AceptarLegalScreen extends StatefulWidget {
  const AceptarLegalScreen({super.key, required this.pendientes, required this.alAceptar});

  final List<DocumentoLegal> pendientes;
  final VoidCallback alAceptar;

  @override
  State<AceptarLegalScreen> createState() => _AceptarLegalScreenState();
}

class _AceptarLegalScreenState extends State<AceptarLegalScreen> {
  bool _acepta = false;
  bool _enviando = false;

  Future<void> _aceptar() async {
    setState(() => _enviando = true);
    try {
      final quedan = await LegalService.aceptar(widget.pendientes);
      if (!mounted) return;
      if (quedan.isEmpty) {
        HapticFeedback.mediumImpact();
        widget.alAceptar();
      } else {
        mostrarError(context, 'Se publicó otra versión mientras leías. Revísala de nuevo');
        setState(() => (_enviando = false, _acepta = false));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      mostrarError(context, textoDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    final varios = widget.pendientes.length > 1;
    return PopScope(
      canPop: false,
      child: FondoValle(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Icon(Icons.verified_user_rounded, size: 56, color: c.primario),
              const SizedBox(height: 12),
              Text('Antes de continuar', textAlign: TextAlign.center, style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                varios ? 'Actualizamos estos documentos. Léelos y acéptalos para seguir usando ValleXpress.' : 'Actualizamos este documento. Léelo y acéptalo para seguir usando ValleXpress.',
                textAlign: TextAlign.center,
                style: tema.bodyMedium?.copyWith(color: c.textoSuave),
              ),
              const SizedBox(height: 20),
              for (final d in widget.pendientes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TarjetaValle(
                    onTap: () => abrirDocumentoLegal(context, d.id),
                    child: Row(
                      children: [
                        Icon(d.esPrivacidad ? Icons.privacy_tip_rounded : Icons.description_rounded, color: c.primario),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.titulo, style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              Text('Versión ${d.version} · desde el ${fechaLegal(d.vigencia)}', style: tema.bodySmall?.copyWith(color: c.textoSuave)),
                              if (d.resumen.isNotEmpty) ...[const SizedBox(height: 4), Text(d.resumen, style: tema.bodySmall)],
                              const SizedBox(height: 6),
                              Text('Leer', style: tema.labelLarge?.copyWith(color: c.primario, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _acepta,
                onChanged: _enviando ? null : (v) => setState(() => _acepta = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(varios ? 'Leí y acepto estos documentos' : 'Leí y acepto este documento'),
              ),
              const SizedBox(height: 8),
              BotonValle(texto: 'Aceptar y continuar', icono: Icons.check_rounded, cargando: _enviando, onPressed: _acepta ? _aceptar : null),
              const SizedBox(height: 8),
              TextButton(onPressed: _enviando ? null : () => context.read<AuthProvider>().logout(), child: const Text('Ahora no, cerrar sesión')),
            ],
          ),
        ),
      ),
    );
  }
}
