/// Application font choices. KT Kiyosuna Sans is bundled with the app under
/// SIL OFL 1.1; the system option clears the family and uses the platform
/// default.
abstract final class AppFonts {
  static const String kiyosuna = 'KT Kiyosuna Sans';
  static const String system = '';

  static const List<String> values = [kiyosuna, system];

  static String label(String family) {
    return family == system ? '系统默认' : 'Kiyosuna Sans（内置）';
  }

  static String sanitize(String? value) {
    if (value == system || value == kiyosuna) return value!;
    return kiyosuna;
  }
}
