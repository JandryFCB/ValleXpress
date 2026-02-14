import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../providers/auth_provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/terms_and_conditions_modal.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String? _selectedRole;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;

  // Email verification state
  bool _isEmailVerified = false;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _codeSent = false; // ✅ Solo mostrar campo después de enviar
  int _retryAfterSeconds = 0;
  Timer? _retryTimer;
  final TextEditingController _codeController = TextEditingController();

  // ✅ Validación en tiempo real de campos únicos
  bool? _cedulaExists;
  bool? _emailExists;
  bool? _placaExists;
  bool _isCheckingCedula = false;
  bool _isCheckingEmail = false;
  bool _isCheckingPlaca = false;

  // ✅ Variables para recordar últimos valores validados (evita re-validar)
  String _lastCheckedCedula = '';
  String _lastCheckedEmail = '';
  String _lastCheckedPlaca = '';

  // FocusNodes para detectar cuando pierden foco
  final FocusNode _cedulaFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _placaFocus = FocusNode();

  // Controllers
  late TextEditingController _nombreController;
  late TextEditingController _apellidoController;
  late TextEditingController _emailController;
  late TextEditingController _telefonoController;
  late TextEditingController _cedulaController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;

  // Campos específicos por rol
  late TextEditingController _nombreNegocioController;
  late TextEditingController _vehiculoController;
  late TextEditingController _placaController;

  Timer? _emailDebounceTimer;
  Timer? _cedulaDebounceTimer;
  Timer? _placaDebounceTimer;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _apellidoController = TextEditingController();
    _emailController = TextEditingController();
    _telefonoController = TextEditingController();
    _cedulaController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _nombreNegocioController = TextEditingController();
    _vehiculoController = TextEditingController();
    _placaController = TextEditingController();

    // Agregar listeners para validación onBlur
    _cedulaFocus.addListener(_onCedulaFocusChange);
    _emailFocus.addListener(_onEmailFocusChange);
    _placaFocus.addListener(_onPlacaFocusChange);

    // ✅ Validación en tiempo real para email (con debounce)
    _emailController.addListener(_onEmailChanged);

    // ✅ Validación en tiempo real para cédula (con debounce)
    _cedulaController.addListener(_onCedulaChanged);

    // ✅ Validación en tiempo real para placa (con debounce)
    _placaController.addListener(_onPlacaChanged);
  }

  // ✅ Validar cédula en tiempo real (con debounce de 500ms)
  void _onCedulaChanged() {
    final cedula = _cedulaController.text.trim();

    // Cancelar timer anterior
    _cedulaDebounceTimer?.cancel();

    // Resetear estado si está vacío o inválido
    if (cedula.isEmpty || cedula.length != 10) {
      setState(() {
        _cedulaExists = null;
        _isCheckingCedula = false;
      });
      return;
    }

    // ✅ NO validar si ya validamos este mismo valor antes
    if (cedula == _lastCheckedCedula && _cedulaExists != null) {
      return;
    }

    // Esperar 500ms después de que el usuario deje de escribir
    _cedulaDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _cedulaController.text.trim().length == 10) {
        _checkCedula();
      }
    });
  }

  // ✅ Validar cédula cuando pierde foco
  void _onCedulaFocusChange() {
    if (!_cedulaFocus.hasFocus && _cedulaController.text.length == 10) {
      // Solo validar si no lo hemos validado antes con este valor
      final cedula = _cedulaController.text.trim();
      if (cedula != _lastCheckedCedula || _cedulaExists == null) {
        _checkCedula();
      }
    }
  }

  // ✅ Validar email en tiempo real (con debounce de 500ms)
  void _onEmailChanged() {
    final email = _emailController.text.trim();

    // Cancelar timer anterior
    _emailDebounceTimer?.cancel();

    // Resetear estado si está vacío o inválido
    if (email.isEmpty || !_validarEmail(email)) {
      setState(() {
        _emailExists = null;
        _isCheckingEmail = false;
      });
      return;
    }

    // ✅ NO validar si ya validamos este mismo valor antes
    if (email == _lastCheckedEmail && _emailExists != null) {
      return;
    }

    // Esperar 500ms después de que el usuario deje de escribir
    _emailDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _validarEmail(_emailController.text.trim())) {
        _checkEmail();
      }
    });
  }

  // ✅ Validar email cuando pierde foco
  void _onEmailFocusChange() {
    if (!_emailFocus.hasFocus && _validarEmail(_emailController.text)) {
      // Solo validar si no lo hemos validado antes con este valor
      final email = _emailController.text.trim();
      if (email != _lastCheckedEmail || _emailExists == null) {
        _checkEmail();
      }
    }
  }

  // ✅ Validar placa en tiempo real (con debounce de 500ms)
  void _onPlacaChanged() {
    final placa = _placaController.text.trim().toUpperCase();

    // Cancelar timer anterior
    _placaDebounceTimer?.cancel();

    // Resetear estado si está vacío
    if (placa.isEmpty) {
      setState(() {
        _placaExists = null;
        _isCheckingPlaca = false;
      });
      return;
    }

    // ✅ NO validar si ya validamos este mismo valor antes
    if (placa == _lastCheckedPlaca && _placaExists != null) {
      return;
    }

    // Esperar 500ms después de que el usuario deje de escribir
    _placaDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _placaController.text.trim().isNotEmpty) {
        _checkPlaca();
      }
    });
  }

  // ✅ Validar placa cuando pierde foco

  void _onPlacaFocusChange() {
    if (!_placaFocus.hasFocus && _placaController.text.isNotEmpty) {
      // Solo validar si no lo hemos validado antes con este valor
      final placa = _placaController.text.trim().toUpperCase();
      if (placa != _lastCheckedPlaca || _placaExists == null) {
        _checkPlaca();
      }
    }
  }

  // ✅ Verificar cédula en backend
  Future<void> _checkCedula() async {
    final cedula = _cedulaController.text.trim();
    if (cedula.length != 10) return;

    setState(() => _isCheckingCedula = true);

    try {
      final authService = AuthService();
      final result = await authService.checkCedula(cedula);

      if (mounted) {
        setState(() {
          _cedulaExists = result['exists'] as bool;
          _isCheckingCedula = false;
          _lastCheckedCedula = cedula; // ✅ Guardar valor validado
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingCedula = false);
    }
  }

  // ✅ Verificar email en backend
  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (!_validarEmail(email)) return;

    setState(() => _isCheckingEmail = true);

    try {
      final authService = AuthService();
      final result = await authService.checkEmail(email);

      if (mounted) {
        setState(() {
          _emailExists = result['exists'] as bool;
          _isCheckingEmail = false;
          _lastCheckedEmail = email; // ✅ Guardar valor validado
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingEmail = false);
    }
  }

  // ✅ Verificar placa en backend
  Future<void> _checkPlaca() async {
    final placa = _placaController.text.trim().toUpperCase();
    if (placa.isEmpty) return;

    setState(() => _isCheckingPlaca = true);

    try {
      final authService = AuthService();
      final result = await authService.checkPlaca(placa);

      if (mounted) {
        setState(() {
          _placaExists = result['exists'] as bool;
          _isCheckingPlaca = false;
          _lastCheckedPlaca = placa; // ✅ Guardar valor validado
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingPlaca = false);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _emailDebounceTimer?.cancel();
    _cedulaDebounceTimer?.cancel();
    _placaDebounceTimer?.cancel();
    _nombreController.dispose();

    _apellidoController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _cedulaController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nombreNegocioController.dispose();
    _vehiculoController.dispose();
    _placaController.dispose();
    _codeController.dispose();
    _cedulaFocus.dispose();
    _emailFocus.dispose();
    _placaFocus.dispose();
    super.dispose();
  }

  // ⏱️ Iniciar countdown para reenvío
  void _startRetryCountdown(int seconds) {
    _retryTimer?.cancel();
    setState(() => _retryAfterSeconds = seconds);

    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_retryAfterSeconds > 0) {
            _retryAfterSeconds--;
          } else {
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  // ✅ Validar teléfono ecuatoriano (09XXXXXXXX)
  bool _validarTelefono(String telefono) {
    final limpio = telefono.replaceAll(RegExp(r'[\s\-]'), '');
    return RegExp(r'^\d{10}$').hasMatch(limpio) && limpio.startsWith('09');
  }

  // ✅ Validar email
  bool _validarEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  // 📧 Enviar código de verificación
  Future<void> _enviarCodigoVerificacion() async {
    final email = _emailController.text.trim();
    final nombre = _nombreController.text.trim();

    if (email.isEmpty || !_validarEmail(email)) {
      _showError('Ingresa un email válido');
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      final authService = AuthService();

      // Obtener FCM token si está disponible
      String? fcmToken;
      try {
        final fcm = FirebaseMessaging.instance;
        fcmToken = await fcm.getToken();
      } catch (e) {
        debugPrint('No se pudo obtener FCM token: $e');
      }

      await authService.sendEmailVerification(
        email,
        nombre,
        fcmToken: fcmToken,
      );

      if (mounted) {
        setState(() {
          _codeSent = true; // ✅ Mostrar campo de código
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '📧 Código enviado. Revisa tu email y notificaciones.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        // ⏱️ Iniciar countdown de 60 segundos después de enviar exitosamente
        _startRetryCountdown(60);
      }
    } catch (e) {
      // Verificar si es error de rate limiting (429)
      final errorStr = e.toString();
      final retryMatch = RegExp(r'Espera (\d+) segundos').firstMatch(errorStr);
      if (retryMatch != null) {
        final seconds = int.parse(retryMatch.group(1)!);
        _startRetryCountdown(seconds);
        _showError('Espera $seconds segundos antes de solicitar otro código');
      } else {
        _showError('Error al enviar código: $e');
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  // ✅ Verificar código ingresado
  Future<void> _verificarCodigo() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (code.length != 6) {
      _showError('El código debe tener 6 dígitos');
      return;
    }

    setState(() => _isVerifyingCode = true);

    try {
      final authService = AuthService();
      final result = await authService.verifyEmailCode(email, code);

      if (result['verified'] == true) {
        setState(() => _isEmailVerified = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Email verificado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _showError('Código incorrecto o expirado');
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  void _handleRegister(BuildContext context) {
    // Validaciones básicas
    if (_selectedRole == null) {
      _showError('Por favor selecciona un rol');
      return;
    }

    if (_nombreController.text.isEmpty ||
        _apellidoController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _telefonoController.text.isEmpty ||
        _cedulaController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      _showError('Por favor completa todos los campos');
      return;
    }

    if (_cedulaController.text.length != 10) {
      _showError('La cédula debe tener 10 dígitos');
      return;
    }

    if (!_validarTelefono(_telefonoController.text)) {
      _showError(
        'El teléfono debe tener 10 dígitos y empezar con 09 (ej: 0991234567)',
      );
      return;
    }

    if (!_isEmailVerified) {
      _showError('Debes verificar tu email antes de registrarte');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Las contraseñas no coinciden');
      return;
    }

    if (_passwordController.text.length < 6) {
      _showError('La contraseña debe tener al menos 6 caracteres');
      return;
    }

    if (!_acceptTerms) {
      _showError('Debes aceptar los términos y condiciones');
      return;
    }

    // Campos específicos según rol
    if (_selectedRole == 'vendedor' && _nombreNegocioController.text.isEmpty) {
      _showError('Por favor ingresa el nombre del negocio');
      return;
    }

    if (_selectedRole == 'repartidor' &&
        (_vehiculoController.text.isEmpty || _placaController.text.isEmpty)) {
      _showError('Por favor completa los datos del vehículo');
      return;
    }

    // Llamar al provider para registrarse
    context
        .read<AuthProvider>()
        .register(
          nombre: _nombreController.text,
          apellido: _apellidoController.text,
          email: _emailController.text,
          telefono: _telefonoController.text,
          cedula: _cedulaController.text,
          password: _passwordController.text,
          tipoUsuario: _selectedRole!,
          nombreNegocio: _selectedRole == 'vendedor'
              ? _nombreNegocioController.text
              : null,
          vehiculo: _selectedRole == 'repartidor'
              ? _vehiculoController.text
              : null,
          placa: _selectedRole == 'repartidor' ? _placaController.text : null,
        )
        .then((success) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Registrado exitosamente!'),
                backgroundColor: Colors.green,
              ),
            );
            // Ir al login
            Navigator.of(context).pushReplacementNamed(AppConstants.loginRoute);
          } else {
            _showError(
              context.read<AuthProvider>().error ?? 'Error al registrar',
            );
          }
        });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Logo con glow dorado
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.cardColor, AppTheme.cardColorLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 80,
                    height: 80,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Título con gradiente
              Center(
                child: ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.accentColor],
                  ).createShader(bounds),
                  child: Text(
                    'Crear Cuenta',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Center(
                child: Text(
                  'Únete a ValleXpress',
                  style: TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Selector de Rol
              Text(
                'Selecciona tu rol',
                style: TextStyle(
                  color: AppTheme.textPrimaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              // Radio buttons para roles
              Column(
                children: [
                  _buildRoleOption('cliente', '👤 Cliente'),
                  const SizedBox(height: 12),
                  _buildRoleOption('vendedor', '🏪 Vendedor'),
                  const SizedBox(height: 12),
                  _buildRoleOption('repartidor', '🚚 Repartidor'),
                ],
              ),

              const SizedBox(height: 24),

              // Formulario de registro
              if (_selectedRole != null) ...[
                // Nombre
                _buildStyledInput(
                  controller: _nombreController,
                  hintText: 'Nombre',
                  icon: Icons.person_outline,
                ),

                const SizedBox(height: 16),

                // Apellido
                _buildStyledInput(
                  controller: _apellidoController,
                  hintText: 'Apellido',
                  icon: Icons.person_outline,
                ),

                const SizedBox(height: 16),

                // Cédula con validación en tiempo real
                _buildStyledInput(
                  controller: _cedulaController,
                  focusNode: _cedulaFocus,
                  hintText: 'Cédula ejm: 0123456789 - 10 dígitos',
                  icon: Icons.credit_card_outlined,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  errorText: _cedulaExists == true
                      ? 'Esta cédula ya está registrada'
                      : null,
                  isValid: _cedulaExists == false,
                  isChecking: _isCheckingCedula,
                ),

                const SizedBox(height: 16),

                // Teléfono con validación
                _buildStyledInput(
                  controller: _telefonoController,
                  hintText: '09XXXXXXXX - 10 dígitos',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                ),

                const SizedBox(height: 16),

                // Email con verificación y validación de duplicado
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStyledInput(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      hintText: 'tu@email.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _emailExists == true
                          ? 'Este email ya está registrado'
                          : null,
                      isValid: _emailExists == false && _isEmailVerified,
                      isChecking: _isCheckingEmail,
                      suffixIcon: _isEmailVerified
                          ? const Icon(Icons.verified, color: Colors.green)
                          : _emailExists == true
                          ? const Icon(Icons.error, color: Colors.red)
                          : _isSendingCode
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed:
                                  (_emailExists == true ||
                                      _retryAfterSeconds > 0)
                                  ? null
                                  : _enviarCodigoVerificacion,
                              child: Text(
                                _retryAfterSeconds > 0
                                    ? 'Espera ${_retryAfterSeconds}s'
                                    : 'Verificar',
                                style: TextStyle(
                                  color:
                                      (_emailExists == true ||
                                          _retryAfterSeconds > 0)
                                      ? Colors.grey
                                      : AppTheme.accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                    // Campo de código (solo cuando se envió y no está verificado)
                    if (_codeSent && !_isEmailVerified) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: InputDecoration(
                                hintText: 'Código de 6 dígitos',
                                hintStyle: TextStyle(
                                  color: AppTheme.textSecondaryColor
                                      .withOpacity(0.5),
                                ),
                                filled: true,
                                fillColor: AppTheme.cardColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                counterText: '',
                              ),
                              style: const TextStyle(
                                color: AppTheme.textPrimaryColor,
                                fontSize: 18,
                                letterSpacing: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _isVerifyingCode
                                ? null
                                : _verificarCodigo,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isVerifyingCode
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Verificar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ingresa el código que te enviamos por email',
                        style: TextStyle(
                          color: AppTheme.textSecondaryColor.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],

                    // Mensaje de verificado (solo cuando está verificado)
                    if (_isEmailVerified) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: const [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Email verificado correctamente',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // Campos específicos por rol
                if (_selectedRole == 'vendedor')
                  Column(
                    children: [
                      _buildStyledInput(
                        controller: _nombreNegocioController,
                        hintText: 'Nombre del negocio',
                        icon: Icons.store_outlined,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                if (_selectedRole == 'repartidor')
                  Column(
                    children: [
                      _buildStyledInput(
                        controller: _vehiculoController,
                        hintText: 'Tipo de vehículo',
                        icon: Icons.two_wheeler_outlined,
                      ),
                      const SizedBox(height: 16),
                      // Placa con validación en tiempo real
                      _buildStyledInput(
                        controller: _placaController,
                        focusNode: _placaFocus,
                        hintText: 'Placa del vehículo (ABC123 o ABC-123)',
                        icon: Icons.confirmation_number_outlined,
                        errorText: _placaExists == true
                            ? 'Esta placa ya está registrada'
                            : null,
                        isValid: _placaExists == false,
                        isChecking: _isCheckingPlaca,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Contraseña
                _buildStyledInput(
                  controller: _passwordController,
                  hintText: '••••••••',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppTheme.textSecondaryColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Confirmar Contraseña
                _buildStyledInput(
                  controller: _confirmPasswordController,
                  hintText: '••••••••',
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppTheme.textSecondaryColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Términos y condiciones
                Row(
                  children: [
                    Checkbox(
                      value: _acceptTerms,
                      onChanged: (value) {
                        setState(() {
                          _acceptTerms = value ?? false;
                        });
                      },
                      activeColor: AppTheme.primaryColor,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => TermsAndConditionsModal(
                                    userRole: _selectedRole ?? 'cliente',
                                  ),
                                );
                              },
                              child: Text(
                                'Acepto los términos y condiciones',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.primaryColor,
                                      decoration: TextDecoration.underline,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Botón Registrarse con gradiente
                Consumer<AuthProvider>(
                  builder: (context, authProvider, _) {
                    return GradientButton(
                      text: 'Crear Cuenta',
                      onPressed: authProvider.isLoading
                          ? null
                          : () => _handleRegister(context),
                      isLoading: authProvider.isLoading,
                      gradientColors: const [
                        AppTheme.primaryColor,
                        Color(0xFFFFA500),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Ya tienes cuenta con estilo vibrante
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '¿Ya tienes cuenta? ',
                        style: TextStyle(
                          color: AppTheme.textSecondaryColor,
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(
                            context,
                          ).pushReplacementNamed(AppConstants.loginRoute);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.accentColor.withOpacity(0.2),
                                AppTheme.accentColor.withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.accentColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'Inicia sesión',
                            style: TextStyle(
                              color: AppTheme.accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption(String value, String label) {
    final isSelected = _selectedRole == value;
    final roleColor = value == 'vendedor'
        ? AppTheme.vendedorColor
        : value == 'repartidor'
        ? AppTheme.repartidorColor
        : AppTheme.clienteColor;

    return Container(
      decoration: BoxDecoration(
        gradient: isSelected
            ? LinearGradient(
                colors: [
                  roleColor.withOpacity(0.2),
                  roleColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isSelected ? null : AppTheme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? roleColor.withOpacity(0.6)
              : AppTheme.borderColor.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: roleColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _selectedRole,
        onChanged: (newValue) {
          setState(() {
            _selectedRole = newValue;
          });
        },
        activeColor: roleColor,
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? roleColor : AppTheme.textSecondaryColor,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildStyledInput({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLength,
    Widget? suffixIcon,
    FocusNode? focusNode,
    String? errorText,
    bool? isValid,
    bool isChecking = false,
  }) {
    // Determinar color del borde según estado
    Color borderColor = AppTheme.borderColor.withOpacity(0.3);
    if (errorText != null) {
      borderColor = Colors.red.withOpacity(0.6);
    } else if (isValid == true) {
      borderColor = Colors.green.withOpacity(0.6);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: errorText != null || isValid == true ? 2 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            obscureText: obscureText,
            maxLength: maxLength,
            style: const TextStyle(color: AppTheme.textPrimaryColor),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: AppTheme.textSecondaryColor.withOpacity(0.5),
              ),
              prefixIcon: Icon(
                icon,
                color: errorText != null ? Colors.red : AppTheme.accentColor,
              ),
              suffixIcon: isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : (isValid == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : suffixIcon),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              counterText: '',
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
