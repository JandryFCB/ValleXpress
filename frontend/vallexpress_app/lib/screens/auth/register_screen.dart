import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/terms_and_conditions_modal.dart';

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
  }

  @override
  void dispose() {
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
    super.dispose();
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

                // Cédula
                _buildStyledInput(
                  controller: _cedulaController,
                  hintText: 'Ejm: 0123456789 - 10 dígitos',
                  icon: Icons.credit_card_outlined,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                ),

                const SizedBox(height: 16),

                // Email
                _buildStyledInput(
                  controller: _emailController,
                  hintText: 'tu@email.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 16),

                // Teléfono
                _buildStyledInput(
                  controller: _telefonoController,
                  hintText: '+593 9 87654321',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
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
                      _buildStyledInput(
                        controller: _placaController,
                        hintText: 'Placa del vehículo',
                        icon: Icons.confirmation_number_outlined,
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.borderColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLength: maxLength,
        style: const TextStyle(color: AppTheme.textPrimaryColor),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppTheme.textSecondaryColor.withOpacity(0.5),
          ),
          prefixIcon: Icon(icon, color: AppTheme.accentColor),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          counterText: '',
        ),
      ),
    );
  }
}
