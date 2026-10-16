import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';
import '../../../utils/validadores.dart';
import '../../../widgets/ui/ui.dart';

/// Lógica del registro en 4 pasos. La pantalla solo dibuja; todo lo demás vive aquí:
///   0 rol · 1 datos personales · 2 verificación del correo · 3 contraseña y términos.
/// Las funciones que pueden fallar devuelven un texto de error (o null si salió bien) para que la pantalla lo muestre.
class RegistroController extends ChangeNotifier {
  RegistroController({AuthService? servicio}) : _servicio = servicio ?? AuthService();

  final AuthService _servicio;

  static const int totalPasos = 4;
  static const List<String> vehiculos = ['Moto', 'Bicicleta', 'Auto', 'Otro'];

  int paso = 0;
  String? rol; // 'cliente' | 'vendedor' | 'repartidor'

  /// Qué perfiles tienen el registro abierto (lo decide el administrador). null = aún no se sabe: se muestran
  /// todos y el servidor vuelve a validar al registrar.
  Map<String, bool>? perfilesAbiertos;
  bool registroAbierto(String valor) => perfilesAbiertos?[valor] ?? true;
  String? vehiculo;
  bool aceptaTerminos = false;

  final nombre = TextEditingController();
  final apellido = TextEditingController();
  final cedula = TextEditingController();
  final telefono = TextEditingController();
  final negocio = TextEditingController();
  final placa = TextEditingController();
  final email = TextEditingController();
  final codigo = TextEditingController();
  final clave = TextEditingController();
  final confirmar = TextEditingController();

  // --- comprobaciones en tiempo real contra el servidor ---
  EstadoCampo estadoCedula = EstadoCampo.neutro;
  String? mensajeCedula;
  EstadoCampo estadoEmail = EstadoCampo.neutro;
  String? mensajeEmail;
  EstadoCampo estadoTelefono = EstadoCampo.neutro;
  String? mensajeTelefono;
  EstadoCampo estadoPlaca = EstadoCampo.neutro;
  String? mensajePlaca;
  Timer? _esperaCedula;
  Timer? _esperaEmail;

  // --- verificación del correo ---
  bool codigoEnviado = false;
  bool enviandoCodigo = false;
  bool verificandoCodigo = false;
  bool emailVerificado = false;
  int segundosEspera = 0;
  Timer? _relojEspera;

  bool registrando = false;
  bool _liberado = false;

  // ---------------------------------------------------------------------------------------------
  // Navegación entre pasos
  // ---------------------------------------------------------------------------------------------
  String get tituloPaso => const ['¿Cómo vas a usar ValleXpress?', 'Cuéntanos de ti', 'Verifica tu correo', 'Crea tu contraseña'][paso];

  String get subtituloPaso => const [
        'Elige tu perfil. Más adelante podrás cambiarlo.',
        'Estos datos nos ayudan a identificarte y a que tus pedidos lleguen bien.',
        'Te enviaremos un código de 6 dígitos para confirmar que el correo es tuyo.',
        'Último paso: protege tu cuenta con una contraseña segura.',
      ][paso];

  /// Devuelve el motivo por el que NO se puede avanzar desde el paso actual (o null si todo está bien).
  String? validarPaso() {
    switch (paso) {
      case 0:
        if (rol == null) return 'Elige cómo vas a usar la app';
        return registroAbierto(rol!) ? null : 'Por ahora no estamos recibiendo este tipo de cuenta';
      case 1:
        if (nombre.text.trim().length < 2) return 'Escribe tu nombre';
        if (apellido.text.trim().isEmpty) return 'Escribe tu apellido';
        if (!Validadores.cedula(cedula.text.trim())) return 'La cédula no es válida: revisa los 10 dígitos';
        if (estadoCedula == EstadoCampo.error) return mensajeCedula ?? 'Esa cédula ya está registrada';
        if (!Validadores.telefono(telefono.text)) return 'El teléfono debe tener 10 dígitos y empezar con 09';
        if (rol == 'vendedor' && negocio.text.trim().isEmpty) return 'Escribe el nombre de tu negocio';
        if (rol == 'repartidor') {
          if (vehiculo == null) return 'Elige tu tipo de vehículo';
          if (!Validadores.placa(placa.text)) return 'La placa no es válida (ej: ABC-123 o AB1234)';
        }
        return null;
      case 2:
        if (!Validadores.email(email.text)) return 'Escribe un correo válido';
        if (!emailVerificado) return 'Verifica tu correo con el código que te enviamos';
        return null;
      default:
        if (clave.text.length < 6) return 'La contraseña debe tener al menos 6 caracteres';
        if (clave.text != confirmar.text) return 'Las contraseñas no coinciden';
        if (!aceptaTerminos) return 'Debes aceptar los términos y condiciones';
        return null;
    }
  }

  /// Avanza al siguiente paso si el actual está completo. Devuelve el error a mostrar, o null si avanzó.
  String? siguiente() {
    final error = validarPaso();
    if (error != null) return error;
    if (paso < totalPasos - 1) {
      paso++;
      _avisar();
    }
    return null;
  }

  bool atras() {
    if (paso == 0) return false;
    paso--;
    _avisar();
    return true;
  }

  void elegirRol(String valor) {
    if (!registroAbierto(valor)) return;
    rol = valor;
    _avisar();
  }

  Future<void> cargarPerfiles() async {
    final perfiles = await _servicio.perfilesRegistro();
    if (perfiles == null || _liberado) return;
    perfilesAbiertos = perfiles;
    if (rol != null && !registroAbierto(rol!)) rol = null;
    _avisar();
  }

  void elegirVehiculo(String? valor) {
    vehiculo = valor;
    _avisar();
  }

  void marcarTerminos(bool valor) {
    aceptaTerminos = valor;
    _avisar();
  }

  /// Refresca la pantalla cuando cambia un campo que influye en el diseño (por ejemplo la fuerza de la clave)
  void campoCambio() => _avisar();

  // ---------------------------------------------------------------------------------------------
  // Comprobaciones en tiempo real (con espera para no consultar en cada tecla)
  // ---------------------------------------------------------------------------------------------
  void alCambiarCedula(String valor) {
    _esperaCedula?.cancel();
    final v = valor.trim();
    if (v.length < 10) {
      estadoCedula = EstadoCampo.neutro;
      mensajeCedula = v.isEmpty ? null : 'Faltan ${10 - v.length} dígitos';
      return _avisar();
    }
    if (!Validadores.cedula(v)) {
      estadoCedula = EstadoCampo.error;
      mensajeCedula = 'Cédula inválida: revisa los dígitos';
      return _avisar();
    }
    estadoCedula = EstadoCampo.comprobando;
    mensajeCedula = 'Comprobando...';
    _avisar();
    _esperaCedula = Timer(const Duration(milliseconds: 450), () async {
      try {
        final r = await _servicio.checkCedula(v);
        if (_liberado || cedula.text.trim() != v) return; // el usuario ya escribió otra cosa
        final existe = r['exists'] == true;
        estadoCedula = existe ? EstadoCampo.error : EstadoCampo.correcto;
        mensajeCedula = existe ? 'Esta cédula ya está registrada' : 'Cédula válida';
      } catch (_) {
        if (_liberado) return;
        estadoCedula = EstadoCampo.neutro; // sin conexión: el servidor la vuelve a validar al registrar
        mensajeCedula = null;
      }
      _avisar();
    });
  }

  void alCambiarTelefono(String valor) {
    final v = valor.replaceAll(RegExp(r'[\s\-]'), '');
    if (v.isEmpty) {
      estadoTelefono = EstadoCampo.neutro;
      mensajeTelefono = null;
    } else if (v.length < 10) {
      estadoTelefono = EstadoCampo.neutro;
      mensajeTelefono = 'Debe empezar con 09 y tener 10 dígitos';
    } else if (!Validadores.telefono(v)) {
      estadoTelefono = EstadoCampo.error;
      mensajeTelefono = 'Debe empezar con 09 y tener 10 dígitos';
    } else {
      estadoTelefono = EstadoCampo.correcto;
      mensajeTelefono = 'Teléfono válido';
    }
    _avisar();
  }

  void alCambiarPlaca(String valor) {
    final v = valor.trim();
    if (v.isEmpty) {
      estadoPlaca = EstadoCampo.neutro;
      mensajePlaca = null;
    } else if (Validadores.placa(v)) {
      estadoPlaca = EstadoCampo.correcto;
      mensajePlaca = 'Placa válida';
    } else {
      estadoPlaca = v.replaceAll(RegExp(r'[\s\-]'), '').length >= 6 ? EstadoCampo.error : EstadoCampo.neutro;
      mensajePlaca = 'Formato: ABC-123 o AB1234';
    }
    _avisar();
  }

  void alCambiarEmail(String valor) {
    _esperaEmail?.cancel();
    // Si cambia el correo, la verificación anterior ya no sirve
    if (emailVerificado || codigoEnviado) {
      emailVerificado = false;
      codigoEnviado = false;
      codigo.clear();
    }
    final v = valor.trim().toLowerCase();
    if (v.isEmpty) {
      estadoEmail = EstadoCampo.neutro;
      mensajeEmail = null;
      return _avisar();
    }
    if (!Validadores.email(v)) {
      estadoEmail = EstadoCampo.neutro;
      mensajeEmail = null;
      return _avisar();
    }
    estadoEmail = EstadoCampo.comprobando;
    mensajeEmail = 'Comprobando...';
    _avisar();
    _esperaEmail = Timer(const Duration(milliseconds: 450), () async {
      try {
        final r = await _servicio.checkEmail(v);
        if (_liberado || email.text.trim().toLowerCase() != v) return;
        final existe = r['exists'] == true;
        estadoEmail = existe ? EstadoCampo.error : EstadoCampo.correcto;
        mensajeEmail = existe ? 'Este correo ya tiene una cuenta. ¿Quieres iniciar sesión?' : 'Correo disponible';
      } catch (_) {
        if (_liberado) return;
        estadoEmail = EstadoCampo.neutro;
        mensajeEmail = null;
      }
      _avisar();
    });
  }

  // ---------------------------------------------------------------------------------------------
  // Verificación del correo
  // ---------------------------------------------------------------------------------------------
  Future<String?> enviarCodigo() async {
    final correo = email.text.trim();
    if (!Validadores.email(correo)) return 'Escribe un correo válido';
    if (estadoEmail == EstadoCampo.error) return mensajeEmail ?? 'Este correo ya está registrado';

    enviandoCodigo = true;
    _avisar();
    try {
      await _servicio.sendEmailVerification(correo, nombre.text.trim(), fcmToken: await _tokenFcm());
      codigoEnviado = true;
      _iniciarEspera(60);
      return null;
    } catch (e) {
      // El servidor pide esperar entre códigos: "Espera 30 segundos antes de solicitar un nuevo código"
      final espera = RegExp(r'Espera (\d+) segundos').firstMatch(e.toString());
      if (espera != null) {
        final s = int.parse(espera.group(1)!);
        codigoEnviado = true;
        _iniciarEspera(s);
        return 'Espera $s segundos antes de pedir otro código';
      }
      return _limpiar(e, 'No pudimos enviar el código. Inténtalo de nuevo.');
    } finally {
      enviandoCodigo = false;
      _avisar();
    }
  }

  Future<String?> verificarCodigo() async {
    final texto = codigo.text.trim();
    if (texto.length != 6) return 'El código tiene 6 dígitos';

    verificandoCodigo = true;
    _avisar();
    try {
      final r = await _servicio.verifyEmailCode(email.text.trim(), texto);
      emailVerificado = r['verified'] == true;
      return emailVerificado ? null : 'Código incorrecto';
    } catch (e) {
      return _limpiar(e, 'Código incorrecto o vencido');
    } finally {
      verificandoCodigo = false;
      _avisar();
    }
  }

  void _iniciarEspera(int segundos) {
    _relojEspera?.cancel();
    segundosEspera = segundos;
    _relojEspera = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_liberado || segundosEspera <= 1) {
        segundosEspera = 0;
        t.cancel();
      } else {
        segundosEspera--;
      }
      _avisar();
    });
    _avisar();
  }

  Future<String?> _tokenFcm() async {
    try {
      return await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null; // sin push el código igual llega por correo
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Crear la cuenta
  // ---------------------------------------------------------------------------------------------
  /// Registra al usuario. Si sale bien, el servidor ya deja la sesión abierta. Devuelve el error o null.
  Future<String?> registrar(AuthProvider auth) async {
    final error = validarPaso();
    if (error != null) return error;

    registrando = true;
    _avisar();
    try {
      final ok = await auth.register(
        nombre: nombre.text.trim(),
        apellido: apellido.text.trim(),
        email: email.text.trim(),
        telefono: telefono.text.replaceAll(RegExp(r'[\s\-]'), ''),
        cedula: cedula.text.trim(),
        password: clave.text,
        tipoUsuario: rol!,
        nombreNegocio: rol == 'vendedor' ? negocio.text.trim() : null,
        vehiculo: rol == 'repartidor' ? vehiculo : null,
        placa: rol == 'repartidor' ? placa.text.trim() : null,
      );
      return ok ? null : (auth.error ?? 'No pudimos crear tu cuenta');
    } finally {
      registrando = false;
      _avisar();
    }
  }

  String _limpiar(Object e, String porDefecto) {
    var t = e.toString();
    t = t.replaceAll('Exception: ', '').replaceAll('Error de conexión: ', '').trim();
    return t.isEmpty ? porDefecto : t;
  }

  void _avisar() {
    if (!_liberado) notifyListeners();
  }

  @override
  void dispose() {
    _liberado = true;
    _esperaCedula?.cancel();
    _esperaEmail?.cancel();
    _relojEspera?.cancel();
    for (final c in [nombre, apellido, cedula, telefono, negocio, placa, email, codigo, clave, confirmar]) {
      c.dispose();
    }
    super.dispose();
  }
}
