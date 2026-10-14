/// Validaciones del lado de la app. Replican las reglas del servidor (backend/src/shared/utils/validators.js) para
/// avisar al usuario ANTES de enviar; el servidor las vuelve a comprobar siempre.
class Validadores {
  Validadores._();

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool email(String v) => _email.hasMatch(v.trim());

  /// Teléfono móvil ecuatoriano: 10 dígitos que empiezan con 09 (se ignoran espacios y guiones)
  static bool telefono(String v) => RegExp(r'^09\d{8}$').hasMatch(v.replaceAll(RegExp(r'[\s\-]'), ''));

  /// Cédula ecuatoriana: 10 dígitos, provincia 01-24 y dígito verificador módulo 10
  static bool cedula(String v) {
    if (!RegExp(r'^\d{10}$').hasMatch(v)) return false;
    final d = v.split('').map(int.parse).toList();
    final provincia = d[0] * 10 + d[1];
    if (provincia < 1 || provincia > 24) return false;
    var suma = 0;
    for (var i = 0; i < 9; i++) {
      final mult = d[i] * (i.isEven ? 2 : 1);
      suma += mult > 9 ? mult - 9 : mult;
    }
    return (10 - (suma % 10)) % 10 == d[9];
  }

  /// Placa: AB1234 (antigua) o ABC123 (nueva); se ignoran guiones y espacios
  static bool placa(String v) =>
      RegExp(r'^([A-Z]{2}\d{4}|[A-Z]{3}\d{3})$').hasMatch(v.toUpperCase().replaceAll(RegExp(r'[\s\-]'), ''));

  /// Fuerza de la contraseña de 0 (vacía) a 4 (fuerte): largo, mayúsculas y minúsculas, números y símbolos.
  static int fuerzaClave(String v) {
    if (v.isEmpty) return 0;
    var puntos = 0;
    if (v.length >= 6) puntos++;
    if (v.length >= 10) puntos++;
    if (RegExp(r'[a-z]').hasMatch(v) && RegExp(r'[A-Z]').hasMatch(v)) puntos++;
    if (RegExp(r'\d').hasMatch(v) && RegExp(r'[^A-Za-z0-9]').hasMatch(v)) puntos++;
    return puntos.clamp(1, 4);
  }

  static String textoFuerza(int fuerza) => switch (fuerza) {
        0 => '',
        1 => 'Débil',
        2 => 'Aceptable',
        3 => 'Buena',
        _ => 'Fuerte',
      };
}
