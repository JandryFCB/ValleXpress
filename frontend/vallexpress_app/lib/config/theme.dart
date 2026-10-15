import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores que cambian según el modo (claro/oscuro). Las pantallas NUEVAS los leen así:
///     final c = context.colores;   ->   c.fondo, c.tarjeta, c.texto, c.textoSuave, c.borde ...
/// Las pantallas que todavía usan las constantes de [AppTheme] (siempre oscuras) se van migrando de a una.
@immutable
class ColoresValle extends ThemeExtension<ColoresValle> {
  const ColoresValle({
    required this.fondo,
    required this.fondoFin,
    required this.tarjeta,
    required this.tarjetaElevada,
    required this.borde,
    required this.texto,
    required this.textoSuave,
    required this.primario,
    required this.acento,
  });

  final Color fondo;
  final Color fondoFin; // segundo color del degradado de fondo
  final Color tarjeta;
  final Color tarjetaElevada;
  final Color borde;
  final Color texto;
  final Color textoSuave;
  final Color primario;
  final Color acento;

  LinearGradient get degradadoFondo =>
      LinearGradient(colors: [fondo, fondoFin], begin: Alignment.topCenter, end: Alignment.bottomCenter);

  @override
  ColoresValle copyWith({
    Color? fondo,
    Color? fondoFin,
    Color? tarjeta,
    Color? tarjetaElevada,
    Color? borde,
    Color? texto,
    Color? textoSuave,
    Color? primario,
    Color? acento,
  }) =>
      ColoresValle(
        fondo: fondo ?? this.fondo,
        fondoFin: fondoFin ?? this.fondoFin,
        tarjeta: tarjeta ?? this.tarjeta,
        tarjetaElevada: tarjetaElevada ?? this.tarjetaElevada,
        borde: borde ?? this.borde,
        texto: texto ?? this.texto,
        textoSuave: textoSuave ?? this.textoSuave,
        primario: primario ?? this.primario,
        acento: acento ?? this.acento,
      );

  @override
  ColoresValle lerp(ThemeExtension<ColoresValle>? other, double t) {
    if (other is! ColoresValle) return this;
    return ColoresValle(
      fondo: Color.lerp(fondo, other.fondo, t)!,
      fondoFin: Color.lerp(fondoFin, other.fondoFin, t)!,
      tarjeta: Color.lerp(tarjeta, other.tarjeta, t)!,
      tarjetaElevada: Color.lerp(tarjetaElevada, other.tarjetaElevada, t)!,
      borde: Color.lerp(borde, other.borde, t)!,
      texto: Color.lerp(texto, other.texto, t)!,
      textoSuave: Color.lerp(textoSuave, other.textoSuave, t)!,
      primario: Color.lerp(primario, other.primario, t)!,
      acento: Color.lerp(acento, other.acento, t)!,
    );
  }
}

extension ColoresContexto on BuildContext {
  ColoresValle get colores => Theme.of(this).extension<ColoresValle>()!;
}

class AppTheme {
  // 🎨 PALETA DEL LOGO "ValleXpress": verde de montaña, amarillo de sol, azul de río y fondo azul marino.
  // Las constantes de abajo son las del modo OSCURO (las pantallas que aún no migraron las leen directo).
  // Para colores que deben cambiar con el modo claro/oscuro usa context.colores.
  static const Color primaryColor = Color(0xFF35B35A); // Verde montaña
  static const Color primaryLight = Color(0xFF7BDC95); // Verde claro
  static const Color primaryDark = Color(0xFF1F7A3A); // Verde profundo

  // 🌌 FONDOS (azul marino del logo)
  static const Color backgroundColor = Color(0xFF0B1A2B);
  static const Color backgroundGradientStart = Color(0xFF0B1A2B);
  static const Color backgroundGradientEnd = Color(0xFF10293F);
  static const Color cardColor = Color(0xFF12263A);
  static const Color cardColorLight = Color(0xFF1A3550);

  // ✨ ACENTOS Y BORDES
  static const Color borderColor = Color(0xFF35B35A);
  static const Color accentColor = Color(0xFFF6B92B); // Amarillo sol
  static const Color accentSecondary = Color(0xFF2F9BE0); // Azul río

  // 📝 TEXTOS
  static const Color textPrimaryColor = Color(0xFFF2F6FA);
  static const Color textSecondaryColor = Color(0xFF9DB2C6);
  static const Color textAccent = Color(0xFF7BDC95);

  // 🎭 COLORES POR ROL
  static const Color vendedorColor = Color(0xFFF6B92B); // Amarillo sol
  static const Color vendedorLight = Color(0xFFFFD066);
  static const Color repartidorColor = Color(0xFF2F9BE0); // Azul río
  static const Color repartidorLight = Color(0xFF6BBBF0);
  static const Color clienteColor = Color(0xFF35B35A); // Verde montaña
  static const Color clienteLight = Color(0xFF7BDC95);

  // 🚦 ESTADOS
  static const Color successColor = Color(0xFF35B35A);
  static const Color errorColor = Color(0xFFFF5A5F);
  static const Color warningColor = Color(0xFFF6B92B);
  static const Color infoColor = Color(0xFF2F9BE0);

  // 🌈 GRADIENTES
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
    colors: [accentColor, Color(0xFFFFD066)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ---------------------------------------------------------------------------------------------
  // Colores por modo
  // ---------------------------------------------------------------------------------------------
  static const ColoresValle _oscuro = ColoresValle(
    fondo: backgroundColor,
    fondoFin: backgroundGradientEnd,
    tarjeta: cardColor,
    tarjetaElevada: cardColorLight,
    borde: Color(0xFF2A4560),
    texto: textPrimaryColor,
    textoSuave: textSecondaryColor,
    primario: primaryColor,
    acento: accentColor,
  );

  static const ColoresValle _claro = ColoresValle(
    fondo: Color(0xFFF4F8F5),
    fondoFin: Color(0xFFE6F1EA),
    tarjeta: Color(0xFFFFFFFF),
    tarjetaElevada: Color(0xFFEEF4F0),
    borde: Color(0xFFD3E0D8),
    texto: Color(0xFF0B1A2B),
    textoSuave: Color(0xFF5A6B7C),
    primario: Color(0xFF1F8F43), // verde más profundo: contrasta bien sobre blanco
    acento: Color(0xFFC98A00),
  );

  static ThemeData get dark => _construir(Brightness.dark, _oscuro);
  static ThemeData get light => _construir(Brightness.light, _claro);

  /// Compatibilidad: las pantallas viejas pedían AppTheme.theme (siempre oscuro)
  static ThemeData get theme => dark;

  static ThemeData _construir(Brightness brillo, ColoresValle c) {
    final oscuro = brillo == Brightness.dark;

    final esquema = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brillo,
    ).copyWith(
      primary: c.primario,
      onPrimary: Colors.white,
      secondary: c.acento,
      onSecondary: oscuro ? backgroundColor : Colors.white,
      surface: c.tarjeta,
      onSurface: c.texto,
      error: errorColor,
      outline: c.borde,
    );

    // Tipografía moderna (Plus Jakarta Sans), con los colores del modo
    final base = GoogleFonts.plusJakartaSansTextTheme(
      oscuro ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(bodyColor: c.texto, displayColor: c.texto);
    final texto = base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, color: c.textoSuave),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    OutlineInputBorder borde(Color color, [double ancho = 1.2]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color, width: ancho));

    return ThemeData(
      useMaterial3: true,
      brightness: brillo,
      colorScheme: esquema,
      scaffoldBackgroundColor: c.fondo,
      canvasColor: c.fondo,
      primaryColor: c.primario,
      textTheme: texto,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      // Cambio de pantalla al estilo de Android moderno: la nueva entra deslizándose y la anterior se desvanece
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: c.texto,
        titleTextStyle: texto.titleLarge?.copyWith(color: c.texto),
      ),

      cardTheme: CardThemeData(
        color: c.tarjeta,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.borde),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.tarjeta,
        border: borde(c.borde),
        enabledBorder: borde(c.borde),
        focusedBorder: borde(c.primario, 2),
        errorBorder: borde(errorColor),
        focusedErrorBorder: borde(errorColor, 2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: texto.bodyMedium?.copyWith(color: c.textoSuave.withValues(alpha: 0.7)),
        labelStyle: texto.bodyMedium,
        prefixIconColor: c.textoSuave,
        suffixIconColor: c.textoSuave,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primario,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          textStyle: texto.labelLarge?.copyWith(fontSize: 16, letterSpacing: 0.3),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primario,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: texto.labelLarge?.copyWith(fontSize: 16),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primario,
          textStyle: texto.labelLarge?.copyWith(fontSize: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primario,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: c.primario, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: texto.labelLarge?.copyWith(fontSize: 16),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.acento,
        foregroundColor: oscuro ? backgroundColor : Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.tarjeta,
        selectedColor: c.primario,
        side: BorderSide(color: c.borde),
        labelStyle: texto.labelMedium?.copyWith(color: c.texto),
        secondaryLabelStyle: texto.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: oscuro ? c.tarjetaElevada : const Color(0xFF16283A),
        contentTextStyle: texto.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: texto.titleLarge,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.tarjeta,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primario.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(texto.labelMedium),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.textoSuave),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primario : c.borde),
      ),

      dividerTheme: DividerThemeData(color: c.borde, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primario),
    );
  }
}
