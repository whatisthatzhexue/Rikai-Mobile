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
enum AgentResponseLanguage {
  follow('follow', '跟随输入'),
  chinese('zh', '中文'),
  english('en', 'English'),
  japanese('ja', '日本語');

  const AgentResponseLanguage(this.wireName, this.label);

  final String wireName;
  final String label;

  static AgentResponseLanguage fromWire(Object? value) {
    for (final item in AgentResponseLanguage.values) {
      if (item.wireName == value) return item;
    }
    return AgentResponseLanguage.follow;
  }

  String get instruction => switch (this) {
    AgentResponseLanguage.follow =>
      'Answer in the same language as the user request; if it is mixed or '
          'unclear, use Simplified Chinese.',
    AgentResponseLanguage.chinese => 'Answer in Simplified Chinese.',
    AgentResponseLanguage.english => 'Answer in English.',
    AgentResponseLanguage.japanese => 'Answer in Japanese.',
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

/// A user-confirmed dictionary familiarization profile.
class DictionaryProfile {
  const DictionaryProfile({
    required this.dictionaryId,
    required this.title,
    required this.kind,
    required this.entryStructure,
    required this.searchBehavior,
    this.languages = const <String>[],
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
    List<String>? strengths,
    List<String>? caveats,
  }) {
    return DictionaryProfile(
      dictionaryId: dictionaryId,
      title: title,
      kind: kind ?? this.kind,
      languages: languages,
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
    return DictionaryProfile(
      dictionaryId: agentString(json['dictionary_id']),
      title: agentString(json['title']),
      kind: agentString(json['kind']),
      languages: agentStringList(json['languages']),
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
    this.profile,
    this.confirmedAt,
    this.modelId = '',
    this.promptVersion = 1,
    this.schemaVersion = 1,
  });

  final String dictionaryId;
  final String fingerprint;
  final String markdown;
  final DictionaryProfileStatus status;
  final DictionaryProfile? profile;
  final DateTime? confirmedAt;
  final String modelId;
  final int promptVersion;
  final int schemaVersion;

  bool get isConfirmed => status == DictionaryProfileStatus.confirmed;
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
