import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // 🎨 PALETA "MEDIANOCHE ELÉCTRICA": violeta vibrante sobre azul casi negro.
  // Cambiando SOLO estos valores se recolorea toda la app (las pantallas leen de aquí).
  static const Color primaryColor = Color(0xFF8B5CF6); // Violeta eléctrico
  static const Color primaryLight = Color(0xFFB794FF); // Violeta claro
  static const Color primaryDark = Color(0xFF6D3FE0); // Violeta profundo

  // 🌌 FONDOS
  static const Color backgroundColor = Color(0xFF0A0E1F); // Azul medianoche
  static const Color backgroundGradientStart = Color(0xFF0A0E1F);
  static const Color backgroundGradientEnd = Color(0xFF171233); // Tinte violeta
  static const Color cardColor = Color(0xFF151B33); // Tarjetas
  static const Color cardColorLight = Color(0xFF212A4D); // Tarjetas elevadas

  // ✨ ACENTOS Y BORDES
  static const Color borderColor = Color(0xFF8B5CF6);
  static const Color accentColor = Color(0xFF22E5C9); // Turquesa neón
  static const Color accentSecondary = Color(0xFFFF5C8A); // Rosa coral

  // 📝 TEXTOS
  static const Color textPrimaryColor = Color(0xFFF5F7FF);
  static const Color textSecondaryColor = Color(0xFF9AA4C7);
  static const Color textAccent = Color(0xFFB794FF);

  // 🎭 COLORES POR ROL (distintos entre sí y del violeta principal)
  static const Color vendedorColor = Color(0xFFFFA62B); // Ámbar
  static const Color vendedorLight = Color(0xFFFFC46B);
  static const Color repartidorColor = Color(0xFF3B9BFF); // Azul cielo
  static const Color repartidorLight = Color(0xFF7CBBFF);
  static const Color clienteColor = Color(0xFF22E5A0); // Verde menta
  static const Color clienteLight = Color(0xFF6DF0C2);

  // 🚦 ESTADOS
  static const Color successColor = Color(0xFF22E5A0);
  static const Color errorColor = Color(0xFFFF4D6D);
  static const Color warningColor = Color(0xFFFFB02E);
  static const Color infoColor = Color(0xFF3BC9FF);

  // 🌈 GRADIENTES PRE-DEFINIDOS
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [backgroundGradientStart, backgroundGradientEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentColor, Color(0xFF3B9BFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,

      // Colores
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: cardColor,
        error: errorColor,
        onPrimary: Colors.white,
      ),

      // Tipografía
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        headlineLarge: GoogleFonts.poppins(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimaryColor,
        ),
        headlineMedium: GoogleFonts.poppins(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimaryColor,
        ),
        bodyLarge: GoogleFonts.poppins(fontSize: 16, color: textPrimaryColor),
        bodyMedium: GoogleFonts.poppins(
          fontSize: 14,
          color: textSecondaryColor,
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: borderColor.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.poppins(color: textSecondaryColor, fontSize: 14),
        labelStyle: GoogleFonts.poppins(
          color: textSecondaryColor,
          fontSize: 14,
        ),
      ),

      // Botones con gradiente y sombras
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: backgroundColor,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          shadowColor: primaryColor.withOpacity(0.4),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Botones de texto
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Botones outline
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Floating action buttons
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: backgroundColor,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        selectedColor: primaryColor,
        labelStyle: GoogleFonts.poppins(fontSize: 12, color: textPrimaryColor),
        secondaryLabelStyle: GoogleFonts.poppins(
          fontSize: 12,
          color: backgroundColor,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
