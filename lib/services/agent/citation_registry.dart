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
