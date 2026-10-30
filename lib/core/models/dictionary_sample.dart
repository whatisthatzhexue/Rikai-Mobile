import 'agent/agent_json.dart';

/// Structural features observed in one sampled MDict entry.
class DictionarySampleFeatures {
  const DictionarySampleFeatures({
    this.hasRuby = false,
    this.hasKanjiInfo = false,
    this.hasExamples = false,
    this.hasAudio = false,
    this.hasImages = false,
    this.hasTables = false,
    this.tagCount = 0,
  });

  final bool hasRuby;
  final bool hasKanjiInfo;
  final bool hasExamples;
  final bool hasAudio;
  final bool hasImages;
  final bool hasTables;
  final int tagCount;

  Map<String, Object?> toJson() => {
    'has_ruby': hasRuby,
    'has_kanji_info': hasKanjiInfo,
    'has_examples': hasExamples,
    'has_audio': hasAudio,
    'has_images': hasImages,
    'has_tables': hasTables,
    'tag_count': tagCount,
  };

  factory DictionarySampleFeatures.fromJson(Map<String, Object?> json) {
    return DictionarySampleFeatures(
      hasRuby: agentBool(json['has_ruby']),
      hasKanjiInfo: agentBool(json['has_kanji_info']),
      hasExamples: agentBool(json['has_examples']),
      hasAudio: agentBool(json['has_audio']),
      hasImages: agentBool(json['has_images']),
      hasTables: agentBool(json['has_tables']),
      tagCount: agentInt(json['tag_count']),
    );
  }
}

/// One bounded dictionary sample. [snippet] is plain text, never raw HTML.
class DictionarySampleEntry {
  const DictionarySampleEntry({
    required this.matchedKey,
    required this.headword,
    required this.snippet,
    required this.features,
  });

  final String matchedKey;
  final String headword;
  final String snippet;
  final DictionarySampleFeatures features;

  Map<String, Object?> toJson() => {
    'matched_key': matchedKey,
    'headword': headword,
    'snippet': snippet,
    'features': features.toJson(),
  };

  factory DictionarySampleEntry.fromJson(Map<String, Object?> json) {
    return DictionarySampleEntry(
      matchedKey: agentString(json['matched_key']),
      headword: agentString(json['headword']),
      snippet: agentString(json['snippet']),
      features: DictionarySampleFeatures.fromJson(agentMap(json['features'])),
    );
  }
}

class DictionarySampleMetadata {
  const DictionarySampleMetadata({
    this.title = '',
    this.entryCount = 0,
    this.encoding = '',
    this.engineVersion = '',
    this.hasMdd = false,
    this.hasCss = false,
  });

  final String title;
  final int entryCount;
  final String encoding;
  final String engineVersion;
  final bool hasMdd;
  final bool hasCss;

  Map<String, Object?> toJson() => {
    'title': title,
    'entry_count': entryCount,
    'encoding': encoding,
    'engine_version': engineVersion,
    'has_mdd': hasMdd,
    'has_css': hasCss,
  };

  factory DictionarySampleMetadata.fromJson(Map<String, Object?> json) {
    return DictionarySampleMetadata(
      title: agentString(json['title']),
      entryCount: agentInt(json['entry_count']),
      encoding: agentString(json['encoding']),
      engineVersion: agentString(json['engine_version']),
      hasMdd: agentBool(json['has_mdd']),
      hasCss: agentBool(json['has_css']),
    );
  }
}

/// Bounded samples for the dictionary familiarization stage.
class DictionarySample {
  const DictionarySample({
    required this.dictionaryId,
    required this.metadata,
    required this.entries,
  });

  final String dictionaryId;
  final DictionarySampleMetadata metadata;
  final List<DictionarySampleEntry> entries;

  Map<String, Object?> toJson() => {
    'dictionary_id': dictionaryId,
    'metadata': metadata.toJson(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  factory DictionarySample.fromJson(Map<String, Object?> json) {
    final rawEntries = json['entries'];
    return DictionarySample(
      dictionaryId: agentString(json['dictionary_id']),
      metadata: DictionarySampleMetadata.fromJson(agentMap(json['metadata'])),
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map(
                  (value) => DictionarySampleEntry.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <DictionarySampleEntry>[],
    );
  }
}
