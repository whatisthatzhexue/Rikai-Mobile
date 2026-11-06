import 'agent_json.dart';

/// Internal tag ids for the built-in coverage word lists.
///
/// These are deliberately language-neutral. UI labels, if added later, are
/// localised separately; the pack format never stores Chinese tag names.
const List<String> wordListTagIds = <String>[
  'greeting',
  'family',
  'food',
  'person_name',
  'place_name',
];

const Map<String, int> wordListTagCounts = <String, int>{
  'greeting': 5,
  'family': 5,
  'food': 5,
  'person_name': 3,
  'place_name': 3,
};

const int wordListTotalEntries = 21;

class WordListEntry {
  const WordListEntry({required this.term, required this.tag});

  final String term;
  final String tag;

  Map<String, Object?> toJson() => <String, Object?>{'term': term, 'tag': tag};

  factory WordListEntry.fromJson(Map<String, Object?> json) {
    return WordListEntry(
      term: agentString(json['term']).trim(),
      tag: agentString(json['tag']).trim().toLowerCase(),
    );
  }
}

/// A static/user-imported coverage word list. It is not a profile-format
/// driver, is not generated on the critical path, and never enters the
/// dictionary profile fingerprint.
class WordListPack {
  const WordListPack({
    required this.id,
    required this.language,
    this.version = 1,
    this.entries = const <WordListEntry>[],
  });

  final String id;
  final String language;
  final int version;
  final List<WordListEntry> entries;

  bool get isValid => validate().isEmpty;

  Map<String, int> get countsByTag {
    final counts = <String, int>{for (final tag in wordListTagIds) tag: 0};
    for (final entry in entries) {
      counts[entry.tag] = (counts[entry.tag] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'language': language,
    'version': version,
    'tags': wordListTagIds,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  factory WordListPack.fromJson(Map<String, Object?> json) {
    final rawEntries = json['entries'];
    return WordListPack(
      id: agentString(json['id']).trim(),
      language: agentString(json['language']).trim().toLowerCase(),
      version: agentInt(json['version'], 1),
      entries: rawEntries is List
          ? <WordListEntry>[
              for (final value in rawEntries.whereType<Map>())
                WordListEntry.fromJson(
                  value.map((key, item) => MapEntry(key.toString(), item)),
                ),
            ]
          : const <WordListEntry>[],
    );
  }

  /// Local-only validation. Import/generation must reject errors before a pack
  /// can be used for coverage metrics.
  List<String> validate() {
    final errors = <String>[];
    if (id.isEmpty) errors.add('词表 id 为空');
    if (!RegExp(r'^[a-z]{2,3}$').hasMatch(language)) {
      errors.add('词表语言代码无效');
    }
    if (version < 1) errors.add('词表版本无效');
    if (entries.length != wordListTotalEntries) {
      errors.add('词表必须正好 $wordListTotalEntries 项，实际 ${entries.length}');
    }
    final counts = countsByTag;
    for (final tag in wordListTagIds) {
      final expected = wordListTagCounts[tag]!;
      if ((counts[tag] ?? 0) != expected) {
        errors.add('标签 $tag 需要 $expected 项，实际 ${counts[tag] ?? 0}');
      }
    }
    final seen = <String>{};
    for (final entry in entries) {
      if (entry.term.isEmpty) {
        errors.add('词表包含空词条');
        continue;
      }
      if (!wordListTagIds.contains(entry.tag)) {
        errors.add('词表包含未知标签 ${entry.tag}');
      }
      final key = entry.term.toLowerCase();
      if (!seen.add(key)) errors.add('词表包含重复词条 ${entry.term}');
    }
    return errors;
  }
}
