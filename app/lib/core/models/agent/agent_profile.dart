import 'agent_json.dart';

/// Language for the human-readable dictionary profile body.
enum AgentProfileLanguage {
  chinese('zh', '中文'),
  english('en', 'English'),
  japanese('ja', '日本語');

  const AgentProfileLanguage(this.wireName, this.label);

  final String wireName;
  final String label;

  static AgentProfileLanguage fromWire(Object? value) {
    for (final item in AgentProfileLanguage.values) {
      if (item.wireName == value) return item;
    }
    return AgentProfileLanguage.chinese;
  }

  String get instruction => switch (this) {
    AgentProfileLanguage.chinese =>
      'Write all human-readable profile text in Simplified Chinese.',
    AgentProfileLanguage.english =>
      'Write all human-readable profile text in English.',
    AgentProfileLanguage.japanese =>
      'Write all human-readable profile text in Japanese.',
  };
}

/// Language of the Agent's answer, separate from the profile language.
///
/// The default is Chinese. Legacy `follow` values are migrated to Chinese when
/// reading stored settings; input-script inference is never used.
enum AgentResponseLanguage {
  chinese('zh', '中文'),
  english('en', 'English'),
  japanese('ja', '日本語');

  const AgentResponseLanguage(this.wireName, this.label);

  final String wireName;
  final String label;

  static AgentResponseLanguage fromWire(Object? value) {
    // 'follow' was removed on 2026-11-01. Existing installs migrate to zh.
    if (value == 'follow') return AgentResponseLanguage.chinese;
    for (final item in AgentResponseLanguage.values) {
      if (item.wireName == value) return item;
    }
    return AgentResponseLanguage.chinese;
  }

  String get instruction => switch (this) {
    AgentResponseLanguage.chinese =>
      'Write every human-readable field (translation, interpretation, word '
          'senses, grammar explanations, unresolved reasons and supplements) '
          'in Simplified Chinese. Source-language forms may appear only in '
          'quoted source text, word forms, readings and dictionary examples. '
          'Pronunciation annotations in [YOMI] blocks are allowed. Do not '
          'answer in Japanese merely when the source text is Japanese.',
    AgentResponseLanguage.english =>
      'Write every human-readable field (translation, interpretation, word '
          'senses, grammar explanations, unresolved reasons and supplements) '
          'in English. Source-language forms may appear only in quoted source '
          'text, word forms, readings and dictionary examples. Pronunciation '
          'annotations in [YOMI] blocks are allowed. Do not answer in '
          'Japanese merely when the source text is Japanese.',
    AgentResponseLanguage.japanese =>
      'Write every human-readable field (translation, interpretation, word '
          'senses, grammar explanations, unresolved reasons and supplements) '
          'in Japanese. Quoted source text, word forms and readings keep their '
          'original form.',
  };
}

/// Structural observations about one MDict dictionary.
class DictionaryEntryStructure {
  const DictionaryEntryStructure({
    this.headwordFields = const <String>[],
    this.definitionFields = const <String>[],
    this.hasRuby = false,
    this.hasKanjiInfo = false,
    this.hasExamples = false,
    this.hasAudio = false,
    this.hasImages = false,
    this.notes = '',
  });

  final List<String> headwordFields;
  final List<String> definitionFields;
  final bool hasRuby;
  final bool hasKanjiInfo;
  final bool hasExamples;
  final bool hasAudio;
  final bool hasImages;
  final String notes;

  Map<String, Object?> toJson() => {
    'headword_fields': headwordFields,
    'definition_fields': definitionFields,
    'has_ruby': hasRuby,
    'has_kanji_info': hasKanjiInfo,
    'has_examples': hasExamples,
    'has_audio': hasAudio,
    'has_images': hasImages,
    if (notes.isNotEmpty) 'notes': notes,
  };

  factory DictionaryEntryStructure.fromJson(Map<String, Object?> json) {
    return DictionaryEntryStructure(
      headwordFields: agentStringList(json['headword_fields']),
      definitionFields: agentStringList(json['definition_fields']),
      hasRuby: agentBool(json['has_ruby']),
      hasKanjiInfo: agentBool(json['has_kanji_info']),
      hasExamples: agentBool(json['has_examples']),
      hasAudio: agentBool(json['has_audio']),
      hasImages: agentBool(json['has_images']),
      notes: agentString(json['notes']),
    );
  }
}

class DictionarySearchBehavior {
  const DictionarySearchBehavior({
    this.exactForms = const <String>[],
    this.prefixSuggestions = false,
    this.notes = '',
  });

  final List<String> exactForms;
  final bool prefixSuggestions;
  final String notes;

  Map<String, Object?> toJson() => {
    'exact_forms': exactForms,
    'prefix_suggestions': prefixSuggestions,
    if (notes.isNotEmpty) 'notes': notes,
  };

  factory DictionarySearchBehavior.fromJson(Map<String, Object?> json) {
    return DictionarySearchBehavior(
      exactForms: agentStringList(json['exact_forms']),
      prefixSuggestions: agentBool(json['prefix_suggestions']),
      notes: agentString(json['notes']),
    );
  }
}

/// One directional dictionary language pair: headword language -> definition
/// language (for example `ja -> zh`).
class DictionaryLanguagePair {
  const DictionaryLanguagePair({
    required this.source,
    required this.target,
    this.confidence = 0,
  });

  final String source;
  final String target;
  final double confidence;

  String get label => '$source→$target';

  Map<String, Object?> toJson() => {
    'source': source,
    'target': target,
    'confidence': confidence,
  };

  factory DictionaryLanguagePair.fromJson(Map<String, Object?> json) {
    return DictionaryLanguagePair(
      source: agentString(json['source']).toLowerCase(),
      target: agentString(json['target']).toLowerCase(),
      confidence: agentDouble(json['confidence']).clamp(0, 1).toDouble(),
    );
  }
}

/// Local, deterministic coverage metrics for one dictionary sample.
class DictionaryCoverage {
  const DictionaryCoverage({
    this.sampleEntries = 0,
    this.entryCount = 0,
    this.headwordScripts = const <String>[],
    this.definitionScripts = const <String>[],
    this.featureCount = 0,
    this.sampleTruncated = false,
    this.unsampledProbeCount = 0,
  });

  final int sampleEntries;
  final int entryCount;
  final List<String> headwordScripts;
  final List<String> definitionScripts;
  final int featureCount;

  /// True when the sampler entry cap stopped at least one probe. The profile is
  /// still usable, but its coverage evidence is incomplete.
  final bool sampleTruncated;

  /// Number of configured probes skipped because of the entry cap.
  final int unsampledProbeCount;

  bool get isEmpty =>
      sampleEntries == 0 &&
      entryCount == 0 &&
      headwordScripts.isEmpty &&
      definitionScripts.isEmpty &&
      featureCount == 0 &&
      !sampleTruncated &&
      unsampledProbeCount == 0;

  Map<String, Object?> toJson() => {
    'sample_entries': sampleEntries,
    'entry_count': entryCount,
    'headword_scripts': headwordScripts,
    'definition_scripts': definitionScripts,
    'feature_count': featureCount,
    if (sampleTruncated) 'sample_truncated': true,
    if (unsampledProbeCount > 0) 'unsampled_probe_count': unsampledProbeCount,
  };

  factory DictionaryCoverage.fromJson(Map<String, Object?> json) {
    return DictionaryCoverage(
      sampleEntries: agentInt(json['sample_entries']),
      entryCount: agentInt(json['entry_count']),
      headwordScripts: agentStringList(json['headword_scripts']),
      definitionScripts: agentStringList(json['definition_scripts']),
      featureCount: agentInt(json['feature_count']),
      sampleTruncated: agentBool(json['sample_truncated']),
      unsampledProbeCount: agentInt(json['unsampled_probe_count']),
    );
  }
}

/// A user-confirmed dictionary familiarization profile.
class DictionaryProfile {
  const DictionaryProfile({
    required this.dictionaryId,
    required this.title,
    required this.kind,
    required this.entryStructure,
    required this.searchBehavior,
    this.languages = const <String>[],
    this.intro = '',
    this.languagePairs = const <DictionaryLanguagePair>[],
    this.coverage = const DictionaryCoverage(),
    this.strengths = const <String>[],
    this.caveats = const <String>[],
    this.recommendedQueryForms = const <String>[],
    this.confidence = 0,
    this.schemaVersion = 1,
    this.language = 'zh',
  });

  static const String schema = 'rikai.dictionary.profile.v1';

  final String dictionaryId;
  final String title;
  final String kind;
  final List<String> languages;

  /// One short sentence describing the dictionary, suitable for a later
  /// dictionary-selection prompt.
  final String intro;

  /// Directional language pairs derived locally from samples and metadata.
  final List<DictionaryLanguagePair> languagePairs;

  /// Deterministic coverage metrics; not generated by the model.
  final DictionaryCoverage coverage;
  final DictionaryEntryStructure entryStructure;
  final DictionarySearchBehavior searchBehavior;
  final List<String> strengths;
  final List<String> caveats;
  final List<String> recommendedQueryForms;
  final double confidence;
  final int schemaVersion;

  /// Language of the human-readable profile body (zh/en/ja).
  final String language;

  DictionaryProfile copyWith({
    String? language,
    String? kind,
    String? intro,
    List<DictionaryLanguagePair>? languagePairs,
    DictionaryCoverage? coverage,
    List<String>? strengths,
    List<String>? caveats,
  }) {
    return DictionaryProfile(
      dictionaryId: dictionaryId,
      title: title,
      kind: kind ?? this.kind,
      languages: languages,
      intro: intro ?? this.intro,
      languagePairs: languagePairs ?? this.languagePairs,
      coverage: coverage ?? this.coverage,
      entryStructure: entryStructure,
      searchBehavior: searchBehavior,
      strengths: strengths ?? this.strengths,
      caveats: caveats ?? this.caveats,
      recommendedQueryForms: recommendedQueryForms,
      confidence: confidence,
      schemaVersion: schemaVersion,
      language: language ?? this.language,
    );
  }

  Map<String, Object?> toJson() => {
    'schema': schema,
    'dictionary_id': dictionaryId,
    'title': title,
    'kind': kind,
    'languages': languages,
    if (intro.isNotEmpty) 'intro': intro,
    if (languagePairs.isNotEmpty)
      'language_pairs': languagePairs.map((pair) => pair.toJson()).toList(),
    if (!coverage.isEmpty) 'coverage': coverage.toJson(),
    'entry_structure': entryStructure.toJson(),
    'search_behavior': searchBehavior.toJson(),
    'strengths': strengths,
    'caveats': caveats,
    'recommended_query_forms': recommendedQueryForms,
    'confidence': confidence,
    'schema_version': schemaVersion,
    'language': language,
  };

  factory DictionaryProfile.fromJson(Map<String, Object?> json) {
    final rawPairs = json['language_pairs'];
    return DictionaryProfile(
      dictionaryId: agentString(json['dictionary_id']),
      title: agentString(json['title']),
      kind: agentString(json['kind']),
      languages: agentStringList(json['languages']),
      intro: agentString(json['intro']),
      languagePairs: rawPairs is List
          ? <DictionaryLanguagePair>[
              for (final value in rawPairs.whereType<Map>())
                DictionaryLanguagePair.fromJson(
                  value.map((key, item) => MapEntry(key.toString(), item)),
                ),
            ]
          : const <DictionaryLanguagePair>[],
      coverage: DictionaryCoverage.fromJson(agentMap(json['coverage'])),
      entryStructure: DictionaryEntryStructure.fromJson(
        agentMap(json['entry_structure']),
      ),
      searchBehavior: DictionarySearchBehavior.fromJson(
        agentMap(json['search_behavior']),
      ),
      strengths: agentStringList(json['strengths']),
      caveats: agentStringList(json['caveats']),
      recommendedQueryForms: agentStringList(json['recommended_query_forms']),
      confidence: agentDouble(json['confidence']),
      schemaVersion: agentInt(json['schema_version'], 1),
      language: AgentProfileLanguage.fromWire(json['language']).wireName,
    );
  }
}

enum DictionaryProfileStatus {
  pending('pending'),
  confirmed('confirmed'),
  declined('declined');

  const DictionaryProfileStatus(this.wireName);

  final String wireName;

  static DictionaryProfileStatus fromWire(Object? value) {
    for (final item in DictionaryProfileStatus.values) {
      if (item.wireName == value) return item;
    }
    return DictionaryProfileStatus.pending;
  }
}

/// Persisted dictionary profile row. The Markdown summary is authoritative for
/// prompts; [profile] is the structured backup.
class StoredDictionaryProfile {
  const StoredDictionaryProfile({
    required this.dictionaryId,
    required this.fingerprint,
    required this.markdown,
    required this.status,
    this.title = '',
    this.profile,
    this.confirmedAt,
    this.modelId = '',
    this.promptVersion = 1,
    this.schemaVersion = 1,
  });

  final String dictionaryId;
  final String title;
  final String fingerprint;
  final String markdown;
  final DictionaryProfileStatus status;
  final DictionaryProfile? profile;
  final DateTime? confirmedAt;
  final String modelId;
  final int promptVersion;
  final int schemaVersion;

  bool get isConfirmed => status == DictionaryProfileStatus.confirmed;

  String get displayTitle =>
      title.trim().isEmpty ? (profile?.title ?? dictionaryId) : title.trim();

  StoredDictionaryProfile copyWith({
    String? title,
    String? markdown,
    DictionaryProfileStatus? status,
    DateTime? confirmedAt,
  }) {
    return StoredDictionaryProfile(
      dictionaryId: dictionaryId,
      title: title ?? this.title,
      fingerprint: fingerprint,
      markdown: markdown ?? this.markdown,
      status: status ?? this.status,
      profile: profile,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      modelId: modelId,
      promptVersion: promptVersion,
      schemaVersion: schemaVersion,
    );
  }
}

/// Deterministic UniDic observations. This is not a dictionary lookup profile.
class UnidicProfile {
  const UnidicProfile({
    this.featureLayout = 29,
    this.observations = const <String>[],
    this.schemaVersion = 1,
  });

  static const String schema = 'rikai.unidic.profile.v1';

  final int featureLayout;
  final List<String> observations;
  final int schemaVersion;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'feature_layout': featureLayout,
    'observations': observations,
    'schema_version': schemaVersion,
  };

  factory UnidicProfile.fromJson(Map<String, Object?> json) {
    return UnidicProfile(
      featureLayout: agentInt(json['feature_layout'], 29),
      observations: agentStringList(json['observations']),
      schemaVersion: agentInt(json['schema_version'], 1),
    );
  }
}

class StoredUnidicProfile {
  const StoredUnidicProfile({
    required this.unidicPathHash,
    required this.fingerprint,
    required this.profile,
    required this.markdown,
    this.confirmedAt,
  });

  final String unidicPathHash;
  final String fingerprint;
  final UnidicProfile profile;
  final String markdown;
  final DateTime? confirmedAt;
}
