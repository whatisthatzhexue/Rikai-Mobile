/// Application font choices. HarmonyOS Sans SC is bundled from a user-supplied
/// font file; the system option clears the font family and uses the platform
/// default.
abstract final class AppFonts {
  static const String harmony = 'HarmonyOS Sans SC';
  static const String system = '';

  static const List<String> values = [harmony, system];

  static String label(String family) {
    return family == system ? '系统默认' : 'HarmonyOS Sans（内置）';
  }

  static String sanitize(String? value) {
    if (value == system || value == harmony) return value!;
    return harmony;
  }
}
