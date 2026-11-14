import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/dict_info.dart';
import '../../core/utils/html_text.dart';

/// Issues and owns citation IDs for one Agent run.
///
/// The model never creates citations; it only sees IDs returned by this
/// registry. Unknown/out-of-run IDs are rejected by the validator.
class CitationRegistry {
  final Map<String, AgentCitation> _citations = <String, AgentCitation>{};
  int _nextId = 1;

  List<AgentCitation> get citations =>
      List<AgentCitation>.unmodifiable(_citations.values);

  /// Number of issued citations without allocating an unmodifiable list.
  int get count => _citations.length;

  AgentCitation? get(String id) => _citations[id];

  AgentCitation? find(String dictionaryId, String entryKey) {
    for (final citation in _citations.values) {
      if (citation.dictionaryId == dictionaryId &&
          citation.entryKey == entryKey) {
        return citation;
      }
    }
    return null;
  }

  void reset() {
    _citations.clear();
    _nextId = 1;
  }

  /// Rehydrates a registry from a cached evidence bundle.
  ///
  /// Cached evidence keeps the IDs issued by the run that built it. A new
  /// registry must know those IDs before coverage can issue supplements;
  /// otherwise `issue` restarts at `source-1` and silently collides with the
  /// cached citations. Existing IDs are never reused.
  void restore(Iterable<AgentCitation> citations) {
    _citations.clear();
    var nextId = 1;
    for (final citation in citations) {
      _citations[citation.id] = citation;
      final match = RegExp(r'^source-(\d+)$').firstMatch(citation.id);
      final issued = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      if (issued >= nextId) nextId = issued + 1;
    }
    _nextId = nextId;
  }

  /// Removes citations that were pruned by local duplicate verification. IDs
  /// are never reused; later citations keep their existing numbers.
  void removeAll(Iterable<String> ids) {
    for (final id in ids) {
      _citations.remove(id);
    }
  }

  AgentCitation issue({
    required String toolCallId,
    required DictionaryInfo dictionary,
    required String entryKey,
    required String headword,
    required String snippet,
    String matchedKey = '',
    String kind = 'mdict',
  }) {
    final id = 'source-${_nextId++}';
    final citation = AgentCitation(
      id: id,
      kind: kind,
      dictionaryId: dictionary.id,
      dictionaryTitle: dictionary.title,
      dictionaryOrder: dictionary.order,
      entryKey: entryKey,
      matchedKey: matchedKey,
      headword: headword,
      snippet: cleanDictionaryText(snippet, maxLength: 240),
      toolCallId: toolCallId,
    );
    _citations[id] = citation;
    return citation;
  }
}
