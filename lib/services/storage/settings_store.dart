import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_fonts.dart';

/// Persisted user preferences.
class AppSettings {
  const AppSettings({
    this.unidicPath = '',
    this.showFurigana = true,
    this.readerFontSize = 20,
    this.fontFamily = AppFonts.harmony,
    this.maxEntriesPerDictionary = 0,
    this.ocrMirror = '',
  });

  final String unidicPath;
  final bool showFurigana;
  final double readerFontSize;

  /// [AppFonts.harmony] or [AppFonts.system] (empty string).
  final String fontFamily;

  /// 0 means unlimited entries per dictionary.
  final int maxEntriesPerDictionary;

  /// Optional custom Hugging Face mirror prefix. Empty uses the manifest URLs
  /// (hf-mirror first, then huggingface.co).
  final String ocrMirror;

  AppSettings copyWith({
    String? unidicPath,
    bool? showFurigana,
    double? readerFontSize,
    String? fontFamily,
    int? maxEntriesPerDictionary,
    String? ocrMirror,
  }) {
    return AppSettings(
      unidicPath: unidicPath ?? this.unidicPath,
      showFurigana: showFurigana ?? this.showFurigana,
      readerFontSize: readerFontSize ?? this.readerFontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      maxEntriesPerDictionary:
          maxEntriesPerDictionary ?? this.maxEntriesPerDictionary,
      ocrMirror: ocrMirror ?? this.ocrMirror,
    );
  }
}

/// Thin typed wrapper around SharedPreferences.
class SettingsStore {
  const SettingsStore(this._preferences);

  static const _unidicPathKey = 'unidic_path';
  static const _showFuriganaKey = 'reader_show_furigana';
  static const _readerFontSizeKey = 'reader_font_size';
  static const _fontFamilyKey = 'app_font_family';
  static const _maxEntriesKey = 'mdict_max_entries_per_dictionary';
  static const _ocrMirrorKey = 'ocr_model_mirror';

  final SharedPreferences _preferences;

  AppSettings load() {
    final storedFont = _preferences.getString(_fontFamilyKey);
    final maxEntries = _preferences.getInt(_maxEntriesKey) ?? 0;
    return AppSettings(
      unidicPath: _preferences.getString(_unidicPathKey) ?? '',
      showFurigana: _preferences.getBool(_showFuriganaKey) ?? true,
      readerFontSize: _preferences.getDouble(_readerFontSizeKey) ?? 20,
      fontFamily: storedFont == null
          ? AppFonts.harmony
          : AppFonts.sanitize(storedFont),
      maxEntriesPerDictionary: maxEntries < 0 ? 0 : maxEntries,
      ocrMirror: _preferences.getString(_ocrMirrorKey) ?? '',
    );
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_unidicPathKey, settings.unidicPath);
    await _preferences.setBool(_showFuriganaKey, settings.showFurigana);
    await _preferences.setDouble(_readerFontSizeKey, settings.readerFontSize);
    await _preferences.setString(_fontFamilyKey, settings.fontFamily);
    await _preferences.setInt(_maxEntriesKey, settings.maxEntriesPerDictionary);
    await _preferences.setString(_ocrMirrorKey, settings.ocrMirror);
  }
}
