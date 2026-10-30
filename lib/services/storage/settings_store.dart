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
    this.onboardingCompleted = false,
    this.autoSaveOcr = false,
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

  /// Whether the first-run setup guide has been completed or skipped.
  final bool onboardingCompleted;

  /// When true, a freshly recognized photo is also written to the corpus.
  /// Manual saving remains available either way.
  final bool autoSaveOcr;

  AppSettings copyWith({
    String? unidicPath,
    bool? showFurigana,
    double? readerFontSize,
    String? fontFamily,
    int? maxEntriesPerDictionary,
    LookupMatchMode? lookupMatchMode,
    String? ocrMirror,
    String? ocrModelsDirectory,
    bool? onboardingCompleted,
    bool? autoSaveOcr,
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
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      autoSaveOcr: autoSaveOcr ?? this.autoSaveOcr,
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
  static const _onboardingCompletedKey = 'app_onboarding_completed';
  static const _autoSaveOcrKey = 'corpus_auto_save_ocr';

  final SharedPreferences _preferences;

  AppSettings load() {
    final storedFont = _preferences.getString(_fontFamilyKey);
    final maxEntries = _preferences.getInt(_maxEntriesKey) ?? 0;
    final storedUnidicPath = _preferences.getString(_unidicPathKey) ?? '';
    // Existing installs predate the onboarding flag. Treat an already
    // configured UniDic path as proof that setup has been done, so an update
    // does not show the welcome guide to current users.
    final onboardingCompleted =
        _preferences.getBool(_onboardingCompletedKey) ??
        storedUnidicPath.trim().isNotEmpty;
    return AppSettings(
      unidicPath: storedUnidicPath,
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
      onboardingCompleted: onboardingCompleted,
      autoSaveOcr: _preferences.getBool(_autoSaveOcrKey) ?? false,
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
    await _preferences.setBool(
      _onboardingCompletedKey,
      settings.onboardingCompleted,
    );
    await _preferences.setBool(_autoSaveOcrKey, settings.autoSaveOcr);
  }

  static LookupMatchMode _lookupModeFromName(String? value) {
    for (final mode in LookupMatchMode.values) {
      if (mode.name == value) return mode;
    }
    return LookupMatchMode.exact;
  }
}
