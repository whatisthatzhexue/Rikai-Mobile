import 'dict_info.dart';

/// One resolved MDX entry.
class LookupEntry {
  const LookupEntry({
    required this.matchedKey,
    required this.headword,
    required this.html,
  });

  /// The key that matched the query before following `@@@LINK` redirects.
  final String matchedKey;

  /// The final entry key after resolving redirects.
  final String headword;

  /// Raw entry HTML returned by `dict_reader`.
  final String html;

  Map<String, Object?> toJson() => {
    'matchedKey': matchedKey,
    'headword': headword,
    'html': html,
  };

  factory LookupEntry.fromMap(Map<Object?, Object?> map) {
    return LookupEntry(
      matchedKey: map['matchedKey'] as String? ?? '',
      headword: map['headword'] as String? ?? '',
      html: map['html'] as String? ?? '',
    );
  }
}

/// Lookup outcome for one dictionary.
class DictionaryLookupGroup {
  const DictionaryLookupGroup({
    required this.dictionary,
    this.entries = const [],
    this.suggestions = const [],
    this.error = '',
  });

  final DictionaryInfo dictionary;
  final List<LookupEntry> entries;
  final List<String> suggestions;

  /// Per-dictionary failure (for example a missing file). Other dictionaries
  /// in the same lookup may still succeed.
  final String error;

  bool get hasHits => entries.isNotEmpty;
}

/// Aggregated lookup outcome across the selected dictionaries.
class LookupResult {
  const LookupResult({
    required this.query,
    required this.candidates,
    required this.groups,
  });

  final String query;

  /// Normalized lookup candidates tried, in order.
  final List<String> candidates;
  final List<DictionaryLookupGroup> groups;

  bool get hasHits => groups.any((group) => group.hasHits);

  List<DictionaryLookupGroup> get hitGroups =>
      groups.where((group) => group.hasHits).toList(growable: false);

  List<String> get suggestions {
    final seen = <String>{};
    final result = <String>[];
    for (final group in groups) {
      for (final suggestion in group.suggestions) {
        if (seen.add(suggestion)) result.add(suggestion);
      }
    }
    return result;
  }
}
