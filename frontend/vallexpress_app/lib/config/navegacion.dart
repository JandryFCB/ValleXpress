import 'package:flutter/material.dart';

/// Llave global del navegador: permite volver al login desde fuera de una pantalla (por ejemplo cuando el
/// servidor cierra la sesión mientras el usuario está en cualquier parte de la app).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
