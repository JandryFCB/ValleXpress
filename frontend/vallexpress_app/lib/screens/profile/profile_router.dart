import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'cliente_profile_screen.dart';
import 'vendedor_profile_screen.dart';
import 'repartidor_profile_screen.dart';

/// Router que redirige al perfil correcto según el tipo de usuario
class ProfileRouter extends StatefulWidget {
  const ProfileRouter({super.key});

  @override
  State<ProfileRouter> createState() => _ProfileRouterState();
}

class _ProfileRouterState extends State<ProfileRouter> {
  String? _tipoUsuario;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _determinarTipoUsuario();
  }

  Future<void> _determinarTipoUsuario() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null || token.isEmpty) {
        // No hay token, redirigir a login
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
        return;
      }

      // Decodificar JWT para obtener tipoUsuario
      final parts = token.split('.');
      if (parts.length != 3) {
        throw Exception('Token inválido');
      }

      // Decodificar payload (segunda parte del JWT)
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payloadMap = jsonDecode(decoded);

      final tipo = payloadMap['tipoUsuario'] ?? 'cliente';

      if (mounted) {
        setState(() {
          _tipoUsuario = tipo;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al determinar tipo de usuario: $e');
      if (mounted) {
        setState(() {
          _tipoUsuario = 'cliente'; // fallback
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Redirigir al screen correcto
    switch (_tipoUsuario) {
      case 'vendedor':
        return const VendedorProfileScreen();
      case 'repartidor':
        return RepartidorProfileScreen();
      case 'cliente':
      default:
        return const ClienteProfileScreen();
    }
  }
}
