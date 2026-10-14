/// Formatos de texto para mostrar en pantalla.
class Formato {
  Formato._();

  /// 0991234567 -> "099 123 4567" (si no tiene 10 dígitos se deja tal cual)
  static String telefono(String numero) {
    final n = numero.replaceAll(RegExp(r'\D'), '');
    return n.length == 10 ? '${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}' : numero;
  }

  /// 8.5 -> "\$8.50"
  static String dinero(num valor) => '\$${valor.toStringAsFixed(2)}';

  /// "luis mora" -> "Luis Mora"
  static String titulo(String texto) => texto
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join(' ');
}
