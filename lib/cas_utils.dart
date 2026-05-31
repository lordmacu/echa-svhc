/// Utilidades para detectar y validar números CAS dentro de texto pegado.
class CasUtils {
  /// Un CAS tiene forma 2–7 dígitos - 2 dígitos - 1 dígito (de control).
  static final RegExp pattern = RegExp(r'(?<![\d-])\d{2,7}-\d{2}-\d(?![\d-])');

  /// Extrae todos los CAS presentes en [text], en orden y sin duplicados.
  static List<String> extractAll(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in pattern.allMatches(text)) {
      final cas = m.group(0)!;
      if (seen.add(cas)) out.add(cas);
    }
    return out;
  }

  /// Verifica el dígito de control del CAS (suma ponderada mod 10).
  /// Útil para avisar de erratas, no para descartar.
  static bool isValidChecksum(String cas) {
    final digits = cas.replaceAll('-', '');
    if (digits.length < 5) return false;
    final check = int.parse(digits[digits.length - 1]);
    var sum = 0;
    var weight = 1;
    for (var i = digits.length - 2; i >= 0; i--) {
      sum += int.parse(digits[i]) * weight;
      weight++;
    }
    return sum % 10 == check;
  }
}
