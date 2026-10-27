import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user preferences.
class AppSettings {
  const AppSettings({
    this.unidicPath = '',
    this.showFurigana = true,
    this.readerFontSize = 20,
  });

  final String unidicPath;
  final bool showFurigana;
  final double readerFontSize;

  AppSettings copyWith({
    String? unidicPath,
    bool? showFurigana,
    double? readerFontSize,
  }) {
    return AppSettings(
      unidicPath: unidicPath ?? this.unidicPath,
      showFurigana: showFurigana ?? this.showFurigana,
      readerFontSize: readerFontSize ?? this.readerFontSize,
    );
  }
}

/// Thin typed wrapper around SharedPreferences.
class SettingsStore {
  const SettingsStore(this._preferences);

  static const _unidicPathKey = 'unidic_path';
  static const _showFuriganaKey = 'reader_show_furigana';
  static const _readerFontSizeKey = 'reader_font_size';

  final SharedPreferences _preferences;

  AppSettings load() {
    return AppSettings(
      unidicPath: _preferences.getString(_unidicPathKey) ?? '',
      showFurigana: _preferences.getBool(_showFuriganaKey) ?? true,
      readerFontSize: _preferences.getDouble(_readerFontSizeKey) ?? 20,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_unidicPathKey, settings.unidicPath);
    await _preferences.setBool(_showFuriganaKey, settings.showFurigana);
    await _preferences.setDouble(_readerFontSizeKey, settings.readerFontSize);
  }
}
