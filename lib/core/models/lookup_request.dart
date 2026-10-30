import 'dict_info.dart';
import 'lookup_match_mode.dart';

/// Explicit, ordered inputs for one dictionary lookup.
///
/// UI and Agent callers both use this model; it never reads global Riverpod
/// state, so dictionary order and selection are reproducible.
class LookupRequest {
  const LookupRequest({
    required this.query,
    required this.dictionaries,
    this.rawCandidates = const <String>[],
    this.matchMode = LookupMatchMode.exact,
    this.maxEntriesPerDictionary = 0,
    this.suggestionLimit = 30,
  });

  final String query;
  final List<String> rawCandidates;

  /// Ordered by the user's dictionary settings.
  final List<DictionaryInfo> dictionaries;
  final LookupMatchMode matchMode;
  final int maxEntriesPerDictionary;
  final int suggestionLimit;
}
