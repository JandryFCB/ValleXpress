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

  /// 14:05
  static String hora(DateTime f) => '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

  /// "Hoy, 14:05" · "Ayer, 09:30" · "12/10, 18:00" (otro año: "12/10/2025")
  static String fechaRelativa(DateTime f) {
    final ahora = DateTime.now();
    final dia = DateTime(f.year, f.month, f.day);
    final diferencia = DateTime(ahora.year, ahora.month, ahora.day).difference(dia).inDays;
    if (diferencia == 0) return 'Hoy, ${hora(f)}';
    if (diferencia == 1) return 'Ayer, ${hora(f)}';
    final dd = f.day.toString().padLeft(2, '0');
    final mm = f.month.toString().padLeft(2, '0');
    return f.year == ahora.year ? '$dd/$mm, ${hora(f)}' : '$dd/$mm/${f.year}';
  }

  /// "hace un momento" · "hace 5 min" · "hace 2 h" · o la fecha relativa si pasó más de un día
  static String hace(DateTime f) {
    final d = DateTime.now().difference(f);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return fechaRelativa(f);
  }

  /// "luis mora" -> "Luis Mora"
  static String titulo(String texto) => texto
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join(' ');
}
