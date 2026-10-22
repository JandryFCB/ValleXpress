import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/pedido.dart' show Vehiculo;
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/validadores.dart';
import '../legal/documento_legal_screen.dart';
import '../../utils/contacto.dart';
import '../../widgets/ui/ui.dart';
import 'registro/registro_controller.dart';

/// Registro en 4 pasos (rol, datos, verificación del correo, contraseña). La lógica está en [RegistroController];
/// esta pantalla solo dibuja. Al terminar, el servidor ya deja la sesión abierta: se entra directo a la app.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.servicio});

  /// Solo para pruebas: permite usar un servicio falso en lugar de llamar al servidor
  final AuthService? servicio;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final RegistroController _c;
  String? _error; // motivo por el que no se puede avanzar (se muestra sobre el botón)

  @override
  void initState() {
    super.initState();
    _c = RegistroController(servicio: widget.servicio)
      ..addListener(_alCambiar)
      ..cargarPerfiles();
  }

  void _alCambiar() {
    if (!mounted) return;
    setState(() {
      // El aviso desaparece apenas el usuario corrige lo que faltaba
      if (_error != null && _c.validarPaso() == null) _error = null;
    });
  }

  final _desplazamiento = ScrollController();

  @override
  void dispose() {
    _desplazamiento.dispose();
    _c
      ..removeListener(_alCambiar)
      ..dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    FocusScope.of(context).unfocus();
    if (_c.paso == RegistroController.totalPasos - 1) {
      final auth = context.read<AuthProvider>();
      final error = await _c.registrar(auth);
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
        mostrarError(context, error);
      } else {
        mostrarExito(context, '¡Bienvenido a ValleXpress!');
        Navigator.of(context).pushNamedAndRemoveUntil(AppConstants.homeRoute, (_) => false);
      }
      return;
    }
    final antes = _c.paso;
    final error = _c.siguiente();
    setState(() => _error = error);
    if (_c.paso != antes) _arriba();
  }

  // Cada paso empieza desde arriba (si había bajado en el anterior, no se queda a la mitad)
  void _arriba() {
    if (_desplazamiento.hasClients && _desplazamiento.offset > 0) {
      _desplazamiento.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
  }

  void _atras() {
    FocusScope.of(context).unfocus();
    if (!_c.atras()) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _error = null);
    _arriba();
  }

  @override
  Widget build(BuildContext context) {
    final ultimo = _c.paso == RegistroController.totalPasos - 1;
    final tema = Theme.of(context).textTheme;

    return PopScope(
      canPop: _c.paso == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _atras();
      },
      child: FondoValle(
        zonaSegura: true,
        barraInferior: _barraAccion(context, ultimo: ultimo),
        child: Column(
          children: [
            _Cabecera(paso: _c.paso, total: RegistroController.totalPasos, onAtras: _atras),
            Expanded(
              child: SingleChildScrollView(
                controller: _desplazamiento,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_c.tituloPaso, style: tema.headlineMedium),
                        const SizedBox(height: 8),
                        Text(_c.subtituloPaso, style: tema.bodyMedium),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          // Los pasos se apilan arriba (no centrados): si no, al volver de un paso más largo (vendedor o
                          // repartidor) el anterior aparecía a media altura y saltaba al terminar la animación
                          layoutBuilder: (actual, anteriores) => Stack(
                            alignment: Alignment.topLeft,
                            children: [...anteriores, ?actual],
                          ),
                          transitionBuilder: (hijo, animacion) => FadeTransition(
                            opacity: animacion,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animacion),
                              child: hijo,
                            ),
                          ),
                          child: KeyedSubtree(key: ValueKey(_c.paso), child: _contenidoPaso()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barra inferior con la acción principal. Va en el lugar propio del Scaffold (barraInferior) para que los avisos
  /// flotantes aparezcan POR ENCIMA y nunca tapen el botón.
  Widget _barraAccion(BuildContext context, {required bool ultimo}) {
    final tema = Theme.of(context).textTheme;
    final c = context.colores;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        decoration: BoxDecoration(color: c.tarjeta, border: Border(top: BorderSide(color: c.borde))),
        // heightFactor: 1 = la barra mide solo lo que mide su contenido (un Center solo ocuparía toda la pantalla)
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: AppTheme.errorColor),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: tema.bodySmall?.copyWith(color: AppTheme.errorColor))),
                      ],
                    ),
                  ),
                BotonValle(
                  texto: ultimo ? 'Crear mi cuenta' : 'Continuar',
                  icono: ultimo ? Icons.check_circle_outline : Icons.arrow_forward,
                  cargando: _c.registrando,
                  onPressed: _continuar,
                ),
                if (_c.paso == 0)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Ya tengo una cuenta'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenidoPaso() {
    switch (_c.paso) {
      case 0:
        return _PasoRol(c: _c);
      case 1:
        return _PasoDatos(c: _c);
      case 2:
        return _PasoCorreo(c: _c);
      default:
        return _PasoClave(c: _c);
    }
  }
}

// ===============================================================================================
// Cabecera: flecha atrás + barra de progreso
// ===============================================================================================
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.paso, required this.total, required this.onAtras});

  final int paso;
  final int total;
  final VoidCallback onAtras;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
      child: Row(
        children: [
          IconButton(onPressed: onAtras, icon: const Icon(Icons.arrow_back_ios_new_rounded), tooltip: 'Atrás'),
          Expanded(
            child: Row(
              children: List.generate(total, (i) {
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 5,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: i <= paso ? c.primario : c.borde,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          Text('${paso + 1}/$total', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.textoSuave)),
        ],
      ),
    );
  }
}

// ===============================================================================================
// Paso 0: elegir el rol
// ===============================================================================================
class _PasoRol extends StatelessWidget {
  const _PasoRol({required this.c});

  final RegistroController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TarjetaRol(
          valor: 'cliente',
          icono: Icons.shopping_bag_outlined,
          titulo: 'Cliente',
          descripcion: 'Pide comida, compras, farmacia y más a los negocios de tu zona.',
          color: AppTheme.clienteColor,
          controlador: c,
        ),
        const SizedBox(height: 12),
        _TarjetaRol(
          valor: 'vendedor',
          icono: Icons.storefront_outlined,
          titulo: 'Vendedor',
          descripcion: 'Publica tus productos y recibe pedidos en tu negocio.',
          color: AppTheme.vendedorColor,
          controlador: c,
        ),
        const SizedBox(height: 12),
        _TarjetaRol(
          valor: 'repartidor',
          icono: Icons.two_wheeler_outlined,
          titulo: 'Repartidor',
          descripcion: 'Entrega pedidos y gana por cada envío que completes.',
          color: AppTheme.repartidorColor,
          controlador: c,
        ),
      ],
    );
  }
}

class _TarjetaRol extends StatelessWidget {
  const _TarjetaRol({
    required this.valor,
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
    required this.controlador,
  });

  final String valor;
  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;
  final RegistroController controlador;

  @override
  Widget build(BuildContext context) {
    final seleccionado = controlador.rol == valor;
    final abierto = controlador.registroAbierto(valor);
    final sinCupos = controlador.sinCupos(valor);
    final tema = Theme.of(context).textTheme;
    // Registro cerrado por el administrador: se ve apagado y no se puede elegir
    return Opacity(
      opacity: abierto ? 1 : 0.5,
      child: TarjetaValle(
        onTap: () => controlador.elegirRol(valor),
        colorBorde: seleccionado ? color : null,
        color: seleccionado ? color.withValues(alpha: 0.10) : null,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
              child: Icon(icono, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    abierto
                        ? descripcion
                        : sinCupos
                            ? 'Por ahora no hay cupos. Escríbenos para quedar en la lista de espera o vuelve más adelante.'
                            : 'Por ahora no estamos recibiendo nuevas cuentas de este tipo.',
                    style: tema.bodySmall?.copyWith(color: context.colores.textoSuave),
                  ),
                  if (sinCupos && (controlador.soporteWhatsapp != null || controlador.soporteCorreo != null))
                    Wrap(spacing: 4, children: [
                      if (controlador.soporteWhatsapp != null)
                        TextButton.icon(
                          onPressed: () => abrirWhatsapp(context, controlador.soporteWhatsapp!, mensaje: 'Hola, quiero ser repartidor de ValleXpress. ¿Hay cupos?'),
                          icon: const Icon(Icons.chat_rounded, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      if (controlador.soporteCorreo != null)
                        TextButton.icon(
                          onPressed: () => escribirASoporte(context, controlador.soporteCorreo!, asunto: 'Quiero ser repartidor de ValleXpress'),
                          icon: const Icon(Icons.mail_outline_rounded, size: 18),
                          label: const Text('Correo'),
                        ),
                    ]),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: !abierto
                  ? Icon(Icons.lock_clock_rounded, key: const ValueKey('cerrado'), color: context.colores.textoSuave)
                  : seleccionado
                      ? Icon(Icons.check_circle, key: const ValueKey('si'), color: color)
                      : Icon(Icons.radio_button_unchecked, key: const ValueKey('no'), color: context.colores.borde),
            ),
          ],
        ),
      ),
    );
  }
}

// ===============================================================================================
// Paso 1: datos personales (y del negocio o vehículo según el rol)
// ===============================================================================================
class _PasoDatos extends StatelessWidget {
  const _PasoDatos({required this.c});

  final RegistroController c;

  @override
  Widget build(BuildContext context) {
    final soloDigitos = [FilteringTextInputFormatter.digitsOnly];
    return Column(
      children: [
        CampoValle(
          controller: c.nombre,
          etiqueta: 'Nombres',
          icono: Icons.person_outline,
          mayusculas: TextCapitalization.words,
          autofill: const [AutofillHints.givenName],
          maxLongitud: 100,
          onChanged: (_) => c.campoCambio(),
        ),
        const SizedBox(height: 16),
        CampoValle(
          controller: c.apellido,
          etiqueta: 'Apellidos',
          icono: Icons.person_outline,
          mayusculas: TextCapitalization.words,
          autofill: const [AutofillHints.familyName],
          maxLongitud: 100,
          onChanged: (_) => c.campoCambio(),
        ),
        const SizedBox(height: 16),
        CampoValle(
          controller: c.cedula,
          etiqueta: 'Cédula',
          icono: Icons.badge_outlined,
          tipoTeclado: TextInputType.number,
          formateadores: soloDigitos,
          maxLongitud: 10,
          estado: c.estadoCedula,
          ayuda: c.mensajeCedula,
          onChanged: c.alCambiarCedula,
        ),
        const SizedBox(height: 16),
        CampoValle(
          controller: c.telefono,
          etiqueta: 'Teléfono móvil',
          icono: Icons.phone_iphone_outlined,
          tipoTeclado: TextInputType.phone,
          formateadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]'))],
          maxLongitud: 12,
          autofill: const [AutofillHints.telephoneNumber],
          estado: c.estadoTelefono,
          ayuda: c.mensajeTelefono ?? 'Ej: 0991234567',
          onChanged: c.alCambiarTelefono,
          accion: c.rol == 'cliente' ? TextInputAction.done : TextInputAction.next,
        ),
        if (c.rol == 'vendedor') ...[
          const SizedBox(height: 28),
          const EncabezadoSeccion('Tu negocio', subtitulo: 'Podrás completar el resto de datos después'),
          CampoValle(
            controller: c.negocio,
            etiqueta: 'Nombre del negocio',
            icono: Icons.storefront_outlined,
            mayusculas: TextCapitalization.words,
            maxLongitud: 200,
            accion: TextInputAction.done,
            onChanged: (_) => c.campoCambio(),
          ),
        ],
        if (c.rol == 'repartidor') ...[
          const SizedBox(height: 28),
          const EncabezadoSeccion('Tu vehículo', subtitulo: 'Lo usamos para asignarte pedidos adecuados'),
          DropdownButtonFormField<Vehiculo>(
            initialValue: c.vehiculo,
            decoration: InputDecoration(labelText: 'Tipo de vehículo', prefixIcon: Icon(c.vehiculo?.icono ?? Icons.two_wheeler_outlined)),
            items: [
              for (final v in Vehiculo.values)
                DropdownMenuItem(value: v, child: Row(children: [Icon(v.icono, size: 20), const SizedBox(width: 10), Text(v.etiqueta)])),
            ],
            onChanged: c.elegirVehiculo,
          ),
          // Bicicleta y a pie no llevan placa
          if (c.vehiculo?.llevaPlaca ?? false) ...[
          const SizedBox(height: 16),
          CampoValle(
            controller: c.placa,
            etiqueta: 'Placa',
            icono: Icons.pin_outlined,
            mayusculas: TextCapitalization.characters,
            formateadores: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]'))],
            maxLongitud: 8,
            estado: c.estadoPlaca,
            ayuda: c.mensajePlaca ?? 'Ej: ABC-1234 (auto) o AB-123C (moto)',
            accion: TextInputAction.done,
            onChanged: c.alCambiarPlaca,
          ),
          ],
        ],
      ],
    );
  }
}

// ===============================================================================================
// Paso 2: correo y código de verificación
// ===============================================================================================
class _PasoCorreo extends StatelessWidget {
  const _PasoCorreo({required this.c});

  final RegistroController c;

  Future<void> _enviar(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final error = await c.enviarCodigo();
    if (!context.mounted) return;
    if (error != null) {
      mostrarError(context, error);
    } else {
      mostrarExito(context, 'Código enviado. Revisa tu correo (y la carpeta de spam).');
    }
  }

  Future<void> _verificar(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final error = await c.verificarCodigo();
    if (!context.mounted) return;
    if (error != null) {
      mostrarError(context, error);
    } else {
      mostrarExito(context, 'Correo verificado');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final colores = context.colores;

    if (c.emailVerificado) {
      return TarjetaValle(
        colorBorde: AppTheme.successColor,
        color: AppTheme.successColor.withValues(alpha: 0.08),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: AppTheme.successColor, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Correo verificado', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(c.email.text.trim(), style: tema.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final puedeEnviar = Validadores.email(c.email.text) && c.estadoEmail != EstadoCampo.error && c.segundosEspera == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CampoValle(
          controller: c.email,
          etiqueta: 'Correo electrónico',
          icono: Icons.alternate_email,
          tipoTeclado: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
          sugerencias: false,
          estado: c.estadoEmail,
          ayuda: c.mensajeEmail,
          accion: TextInputAction.done,
          onChanged: c.alCambiarEmail,
        ),
        const SizedBox(height: 16),
        BotonValle(
          texto: c.codigoEnviado
              ? (c.segundosEspera > 0 ? 'Reenviar código en ${c.segundosEspera} s' : 'Reenviar código')
              : 'Enviar código',
          icono: Icons.mark_email_unread_outlined,
          tipo: c.codigoEnviado ? TipoBoton.secundario : TipoBoton.principal,
          cargando: c.enviandoCodigo,
          onPressed: puedeEnviar ? () => _enviar(context) : null,
        ),
        if (c.codigoEnviado) ...[
          const SizedBox(height: 28),
          Text('Escribe el código', style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: c.codigo,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: tema.headlineMedium?.copyWith(letterSpacing: 14, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: tema.headlineMedium?.copyWith(letterSpacing: 14, color: colores.borde),
            ),
            onChanged: (v) {
              c.campoCambio();
              if (v.length == 6) _verificar(context); // se verifica solo al completar los 6 dígitos
            },
          ),
          const SizedBox(height: 16),
          BotonValle(
            texto: 'Verificar código',
            icono: Icons.verified_outlined,
            cargando: c.verificandoCodigo,
            onPressed: c.codigo.text.trim().length == 6 ? () => _verificar(context) : null,
          ),
        ],
      ],
    );
  }
}

// ===============================================================================================
// Paso 3: contraseña y términos
// ===============================================================================================
class _PasoClave extends StatelessWidget {
  const _PasoClave({required this.c});

  final RegistroController c;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final colores = context.colores;
    final coinciden = c.confirmar.text.isNotEmpty && c.clave.text == c.confirmar.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CampoValle(
          controller: c.clave,
          etiqueta: 'Contraseña',
          icono: Icons.lock_outline,
          esClave: true,
          maxLongitud: 72,
          autofill: const [AutofillHints.newPassword],
          onChanged: (_) => c.campoCambio(),
        ),
        const SizedBox(height: 10),
        MedidorClave(clave: c.clave.text),
        const SizedBox(height: 6),
        Text('Usa al menos 6 caracteres. Mezcla mayúsculas, números y símbolos para hacerla más fuerte.',
            style: tema.bodySmall?.copyWith(color: colores.textoSuave)),
        const SizedBox(height: 18),
        CampoValle(
          controller: c.confirmar,
          etiqueta: 'Confirmar contraseña',
          icono: Icons.lock_reset_outlined,
          esClave: true,
          maxLongitud: 72,
          accion: TextInputAction.done,
          estado: c.confirmar.text.isEmpty ? EstadoCampo.neutro : (coinciden ? EstadoCampo.correcto : EstadoCampo.error),
          ayuda: c.confirmar.text.isEmpty ? null : (coinciden ? 'Las contraseñas coinciden' : 'Las contraseñas no coinciden'),
          onChanged: (_) => c.campoCambio(),
        ),
        const SizedBox(height: 24),
        TarjetaValle(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Checkbox(value: c.aceptaTerminos, onChanged: (v) => c.marcarTerminos(v ?? false)),
              Expanded(
                child: GestureDetector(
                  onTap: () => c.marcarTerminos(!c.aceptaTerminos),
                  child: Text.rich(
                    TextSpan(
                      style: tema.bodySmall,
                      children: [
                        const TextSpan(text: 'Acepto los '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () => abrirDocumentoLegal(context, 'terminos-${c.rol ?? 'cliente'}'),
                            child: Text(
                              'términos y condiciones',
                              style: tema.bodySmall?.copyWith(color: colores.primario, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' y la '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () => abrirDocumentoLegal(context, 'privacidad'),
                            child: Text(
                              'política de privacidad',
                              style: tema.bodySmall?.copyWith(color: colores.primario, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' de ValleXpress.'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
