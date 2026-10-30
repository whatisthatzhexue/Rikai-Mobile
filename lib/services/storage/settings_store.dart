import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/lookup_match_mode.dart';
import '../../core/theme/app_fonts.dart';

/// Persisted user preferences.
class AppSettings {
  const AppSettings({
    this.unidicPath = '',
    this.showFurigana = true,
    this.readerFontSize = 20,
    this.fontFamily = AppFonts.harmony,
    this.maxEntriesPerDictionary = 0,
    this.lookupMatchMode = LookupMatchMode.exact,
    this.ocrMirror = '',
    this.ocrModelsDirectory = '',
  });

  final String unidicPath;
  final bool showFurigana;
  final double readerFontSize;

  /// [AppFonts.harmony] or [AppFonts.system] (empty string).
  final String fontFamily;

  /// 0 means unlimited entries per dictionary.
  final int maxEntriesPerDictionary;

  /// Exact/prefix/suffix/incremental matching shared by every lookup surface.
  final LookupMatchMode lookupMatchMode;

  /// Optional custom Hugging Face mirror prefix. Empty uses the manifest URLs
  /// (hf-mirror first, then huggingface.co).
  final String ocrMirror;

  /// User-selected OCR model directory. Empty uses the app's external files
  /// directory (`<external>/models`).
  final String ocrModelsDirectory;

  AppSettings copyWith({
    String? unidicPath,
    bool? showFurigana,
    double? readerFontSize,
    String? fontFamily,
    int? maxEntriesPerDictionary,
    LookupMatchMode? lookupMatchMode,
    String? ocrMirror,
    String? ocrModelsDirectory,
  }) {
    return AppSettings(
      unidicPath: unidicPath ?? this.unidicPath,
      showFurigana: showFurigana ?? this.showFurigana,
      readerFontSize: readerFontSize ?? this.readerFontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      maxEntriesPerDictionary:
          maxEntriesPerDictionary ?? this.maxEntriesPerDictionary,
      lookupMatchMode: lookupMatchMode ?? this.lookupMatchMode,
      ocrMirror: ocrMirror ?? this.ocrMirror,
      ocrModelsDirectory: ocrModelsDirectory ?? this.ocrModelsDirectory,
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
  static const _lookupMatchModeKey = 'mdict_lookup_match_mode';
  static const _ocrMirrorKey = 'ocr_model_mirror';
  static const _ocrModelsDirectoryKey = 'ocr_models_directory';

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
      lookupMatchMode: _lookupModeFromName(
        _preferences.getString(_lookupMatchModeKey),
      ),
      ocrMirror: _preferences.getString(_ocrMirrorKey) ?? '',
      ocrModelsDirectory: _preferences.getString(_ocrModelsDirectoryKey) ?? '',
    );
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_unidicPathKey, settings.unidicPath);
    await _preferences.setBool(_showFuriganaKey, settings.showFurigana);
    await _preferences.setDouble(_readerFontSizeKey, settings.readerFontSize);
    await _preferences.setString(_fontFamilyKey, settings.fontFamily);
    await _preferences.setInt(_maxEntriesKey, settings.maxEntriesPerDictionary);
    await _preferences.setString(
      _lookupMatchModeKey,
      settings.lookupMatchMode.name,
    );
    await _preferences.setString(_ocrMirrorKey, settings.ocrMirror);
    await _preferences.setString(
      _ocrModelsDirectoryKey,
      settings.ocrModelsDirectory,
    );
  }

  static LookupMatchMode _lookupModeFromName(String? value) {
    for (final mode in LookupMatchMode.values) {
      if (mode.name == value) return mode;
    }
    return LookupMatchMode.exact;
  }
}
