import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';

/// Estado de una comprobación en tiempo real (por ejemplo "¿esta cédula ya está registrada?")
enum EstadoCampo { neutro, comprobando, correcto, error }

/// Campo de texto estándar. Un solo lugar para el estilo, el botón de mostrar/ocultar clave y los mensajes de
/// comprobación, en vez de repetirlos en cada pantalla.
///
///     CampoValle(controller: _c, etiqueta: 'Cédula', icono: Icons.badge_outlined, estado: _estado, ayuda: 'Disponible')
class CampoValle extends StatefulWidget {
  const CampoValle({
    super.key,
    required this.controller,
    required this.etiqueta,
    this.icono,
    this.esClave = false,
    this.tipoTeclado,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.accion = TextInputAction.next,
    this.formateadores,
    this.maxLongitud,
    this.mayusculas = TextCapitalization.none,
    this.autofill,
    this.estado = EstadoCampo.neutro,
    this.ayuda,
    this.sufijo,
    this.enabled = true,
    this.readOnly = false,
    this.maxLineas = 1,
    this.sugerencias = true,
  });

  final TextEditingController controller;
  final String etiqueta;
  final IconData? icono;
  final bool esClave;
  final TextInputType? tipoTeclado;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputAction accion;
  final List<TextInputFormatter>? formateadores;
  final int? maxLongitud;
  final TextCapitalization mayusculas;
  final Iterable<String>? autofill;
  final EstadoCampo estado;

  /// Texto pequeño debajo del campo (ayuda, o resultado de la comprobación)
  final String? ayuda;
  final Widget? sufijo;
  final bool enabled;
  final bool readOnly;
  final int maxLineas;
  final bool sugerencias;

  @override
  State<CampoValle> createState() => _CampoValleState();
}

class _CampoValleState extends State<CampoValle> {
  bool _oculto = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;

    Widget? sufijo = widget.sufijo;
    if (widget.esClave) {
      sufijo = IconButton(
        tooltip: _oculto ? 'Mostrar contraseña' : 'Ocultar contraseña',
        icon: Icon(_oculto ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _oculto = !_oculto),
      );
    } else if (widget.estado == EstadoCampo.comprobando) {
      sufijo = Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.primario)),
      );
    } else if (widget.estado == EstadoCampo.correcto) {
      sufijo = const Icon(Icons.check_circle, color: AppTheme.successColor);
    } else if (widget.estado == EstadoCampo.error) {
      sufijo = const Icon(Icons.error_outline, color: AppTheme.errorColor);
    }

    final colorAyuda = widget.estado == EstadoCampo.error
        ? AppTheme.errorColor
        : widget.estado == EstadoCampo.correcto
            ? AppTheme.successColor
            : c.textoSuave;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: widget.esClave && _oculto,
          keyboardType: widget.tipoTeclado,
          textInputAction: widget.accion,
          textCapitalization: widget.mayusculas,
          inputFormatters: [
            if (widget.maxLongitud != null) LengthLimitingTextInputFormatter(widget.maxLongitud),
            ...?widget.formateadores,
          ],
          autofillHints: widget.autofill,
          autocorrect: widget.sugerencias && !widget.esClave,
          enableSuggestions: widget.sugerencias && !widget.esClave,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          minLines: 1,
          maxLines: widget.esClave ? 1 : widget.maxLineas,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            labelText: widget.etiqueta,
            prefixIcon: widget.icono == null ? null : Icon(widget.icono),
            suffixIcon: sufijo,
            counterText: '',
            enabledBorder: widget.estado == EstadoCampo.error
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.4))
                : widget.estado == EstadoCampo.correcto
                    ? OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.successColor, width: 1.4))
                    : null,
          ),
        ),
        if (widget.ayuda != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 6),
            child: Text(widget.ayuda!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorAyuda)),
          ),
      ],
    );
  }
}
