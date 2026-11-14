import '../../../core/models/agent/word_list_pack.dart';
import '../../../core/models/dict_info.dart';
import '../../../core/models/lookup_match_mode.dart';
import '../../../core/models/lookup_request.dart';
import '../../../core/utils/text_normalizer.dart';
import '../ports/lookup_port.dart';

class WordListCoverage {
  const WordListCoverage({
    required this.packId,
    required this.language,
    required this.total,
    required this.hits,
    required this.hitsByTag,
  });

  final String packId;
  final String language;
  final int total;
  final int hits;
  final Map<String, int> hitsByTag;

  double get hitRate => total == 0 ? 0 : hits / total;

  Map<String, Object?> toJson() => <String, Object?>{
    'pack_id': packId,
    'language': language,
    'total': total,
    'hits': hits,
    'hit_rate': hitRate,
    'hits_by_tag': hitsByTag,
  };
}

/// Counts how many pack terms resolve in one dictionary using the same
/// exact -> prefix -> suffix order as the original word-list idea.
///
/// This is local coverage measurement only; it is not sent to a model and is
/// not part of the dictionary profile fingerprint.
Future<WordListCoverage> evaluateWordListCoverage({
  required WordListPack pack,
  required DictionaryInfo dictionary,
  required LookupPort lookupPort,
  bool Function()? isCancelled,
}) async {
  final hitsByTag = <String, int>{for (final tag in wordListTagIds) tag: 0};
  var hits = 0;
  for (final entry in pack.entries) {
    if (isCancelled?.call() == true) break;
    var hit = false;
    for (final mode in const <LookupMatchMode>[
      LookupMatchMode.exact,
      LookupMatchMode.prefix,
      LookupMatchMode.suffix,
    ]) {
      try {
        final result = await lookupPort.lookup(
          LookupRequest(
            query: entry.term,
            rawCandidates: lookupCandidatesFor(<String>[entry.term]),
            dictionaries: <DictionaryInfo>[dictionary],
            matchMode: mode,
            maxEntriesPerDictionary: 1,
            suggestionLimit: 0,
          ),
        );
        if (result.hasHits) {
          hit = true;
          break;
        }
      } catch (_) {
        // One lookup failure is a miss, not a coverage-run failure.
        break;
      }
    }
    if (!hit) continue;
    hits++;
    hitsByTag[entry.tag] = (hitsByTag[entry.tag] ?? 0) + 1;
  }
  return WordListCoverage(
    packId: pack.id,
    language: pack.language,
    total: pack.entries.length,
    hits: hits,
    hitsByTag: Map<String, int>.unmodifiable(hitsByTag),
  );
}
