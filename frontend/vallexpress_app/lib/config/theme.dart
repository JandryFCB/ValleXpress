import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // 🎨 PALETA PRINCIPAL - Colores vibrantes y modernos
  static const Color primaryColor = Color(
    0xFFFFD700,
  ); // Amarillo dorado brillante
  static const Color primaryLight = Color(0xFFFFE44D); // Amarillo claro
  static const Color primaryDark = Color(0xFFFFB800); // Amarillo oscuro

  // 🌊 FONDOS - Azules profundos con más vida
  static const Color backgroundColor = Color(0xFF0D1B2A); // Azul noche profundo
  static const Color backgroundGradientStart = Color(0xFF0D1B2A);
  static const Color backgroundGradientEnd = Color(0xFF1B3A4B);
  static const Color cardColor = Color(0xFF1B3A4B); // Azul acero vibrante
  static const Color cardColorLight = Color(0xFF2C5364); // Variación más clara

  // ✨ ACENTOS Y BORDES
  static const Color borderColor = Color(0xFFFFD700); // Dorado brillante
  static const Color accentColor = Color(0xFF00D4AA); // Turquesa neón
  static const Color accentSecondary = Color(0xFFFF6B6B); // Coral vibrante

  // 📝 TEXTOS
  static const Color textPrimaryColor = Colors.white;
  static const Color textSecondaryColor = Color(0xFF90A4AE);
  static const Color textAccent = Color(0xFFFFD700);

  // 🎭 COLORES POR ROL - Más vibrantes y distintivos
  static const Color vendedorColor = Color(0xFFFF9500); // Naranja neón
  static const Color vendedorLight = Color(0xFFFFB84D);
  static const Color repartidorColor = Color(0xFF1976D2); // Azul brillante
  static const Color repartidorLight = Color(0xFF42A5F5);
  static const Color clienteColor = Color(0xFF06D6A0); // Verde esmeralda
  static const Color clienteLight = Color(0xFF4DEDB8);

  // 🚦 ESTADOS - Colores de acción claros
  static const Color successColor = Color(0xFF00F5A0); // Verde neón
  static const Color errorColor = Color(0xFFFF4757); // Rojo vibrante
  static const Color warningColor = Color(0xFFFFB800); // Ámbar brillante
  static const Color infoColor = Color(0xFF00D4FF); // Azul cielo neón

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
    colors: [accentColor, Color(0xFF00B4D8)],
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
        secondary: primaryColor,
        surface: cardColor,
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
