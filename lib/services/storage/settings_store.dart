import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/agent/agent_profile.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/theme/app_fonts.dart';

/// Persisted user preferences.
class AppSettings {
  const AppSettings({
    this.unidicPath = '',
    this.showFurigana = true,
    this.annotationRuleSetId = 'furigana',
    this.readerFontSize = 20,
    this.fontFamily = AppFonts.harmony,
    this.maxEntriesPerDictionary = 0,
    this.lookupMatchMode = LookupMatchMode.exact,
    this.ocrMirror = '',
    this.ocrModelsDirectory = '',
    this.onboardingCompleted = false,
    this.autoSaveOcr = false,
    this.agentProfileLanguage = 'zh',
    this.agentResponseLanguage = 'zh',
    this.agentProfilesAutoAccept = false,
  });

  final String unidicPath;
  final bool showFurigana;

  /// Built-in annotation rule set id (`furigana`, `furigana_pitch`, `none`).
  /// P6.7 v1 has no user-editable rule text.
  final String annotationRuleSetId;
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

  /// Human-readable language for the dictionary profile body: zh/en/ja.
  final String agentProfileLanguage;

  /// Agent answer language: zh/en/ja. Legacy `follow` is migrated to `zh`.
  final String agentResponseLanguage;

  /// When true, newly generated dictionary profiles are saved without a
  /// confirmation sheet. Defaults to false ("ask every time").
  final bool agentProfilesAutoAccept;

  AppSettings copyWith({
    String? unidicPath,
    bool? showFurigana,
    String? annotationRuleSetId,
    double? readerFontSize,
    String? fontFamily,
    int? maxEntriesPerDictionary,
    LookupMatchMode? lookupMatchMode,
    String? ocrMirror,
    String? ocrModelsDirectory,
    bool? onboardingCompleted,
    bool? autoSaveOcr,
    String? agentProfileLanguage,
    String? agentResponseLanguage,
    bool? agentProfilesAutoAccept,
  }) {
    return AppSettings(
      unidicPath: unidicPath ?? this.unidicPath,
      showFurigana: showFurigana ?? this.showFurigana,
      annotationRuleSetId: annotationRuleSetId ?? this.annotationRuleSetId,
      readerFontSize: readerFontSize ?? this.readerFontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      maxEntriesPerDictionary:
          maxEntriesPerDictionary ?? this.maxEntriesPerDictionary,
      lookupMatchMode: lookupMatchMode ?? this.lookupMatchMode,
      ocrMirror: ocrMirror ?? this.ocrMirror,
      ocrModelsDirectory: ocrModelsDirectory ?? this.ocrModelsDirectory,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      autoSaveOcr: autoSaveOcr ?? this.autoSaveOcr,
      agentProfileLanguage: AgentProfileLanguage.fromWire(
        agentProfileLanguage ?? this.agentProfileLanguage,
      ).wireName,
      agentResponseLanguage: AgentResponseLanguage.fromWire(
        agentResponseLanguage ?? this.agentResponseLanguage,
      ).wireName,
      agentProfilesAutoAccept:
          agentProfilesAutoAccept ?? this.agentProfilesAutoAccept,
    );
  }
}

/// Thin typed wrapper around SharedPreferences.
class SettingsStore {
  const SettingsStore(this._preferences);

  static const _unidicPathKey = 'unidic_path';
  static const _showFuriganaKey = 'reader_show_furigana';
  static const _annotationRuleSetKey = 'reader_annotation_rule_set';
  static const _readerFontSizeKey = 'reader_font_size';
  static const _fontFamilyKey = 'app_font_family';
  static const _maxEntriesKey = 'mdict_max_entries_per_dictionary';
  static const _lookupMatchModeKey = 'mdict_lookup_match_mode';
  static const _ocrMirrorKey = 'ocr_model_mirror';
  static const _ocrModelsDirectoryKey = 'ocr_models_directory';
  static const _onboardingCompletedKey = 'app_onboarding_completed';
  static const _autoSaveOcrKey = 'corpus_auto_save_ocr';
  static const _agentProfileLanguageKey = 'agent_profile_language';
  static const _agentResponseLanguageKey = 'agent_response_language';
  static const _agentProfilesAutoAcceptKey = 'agent_profiles_auto_accept';

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
      annotationRuleSetId:
          _preferences.getString(_annotationRuleSetKey) ?? 'furigana',
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
      agentProfileLanguage: AgentProfileLanguage.fromWire(
        _preferences.getString(_agentProfileLanguageKey),
      ).wireName,
      agentResponseLanguage: AgentResponseLanguage.fromWire(
        _preferences.getString(_agentResponseLanguageKey),
      ).wireName,
      agentProfilesAutoAccept:
          _preferences.getBool(_agentProfilesAutoAcceptKey) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_unidicPathKey, settings.unidicPath);
    await _preferences.setBool(_showFuriganaKey, settings.showFurigana);
    await _preferences.setString(
      _annotationRuleSetKey,
      settings.annotationRuleSetId,
    );
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
    await _preferences.setString(
      _agentProfileLanguageKey,
      settings.agentProfileLanguage,
    );
    await _preferences.setString(
      _agentResponseLanguageKey,
      settings.agentResponseLanguage,
    );
    await _preferences.setBool(
      _agentProfilesAutoAcceptKey,
      settings.agentProfilesAutoAccept,
    );
  }

  static LookupMatchMode _lookupModeFromName(String? value) {
    for (final mode in LookupMatchMode.values) {
      if (mode.name == value) return mode;
    }
    return LookupMatchMode.exact;
  }
}
