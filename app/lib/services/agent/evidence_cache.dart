import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/dict_info.dart';
import 'agent_run.dart';

/// In-memory LRU for text-run evidence. The cache never contains images,
/// paths, base64 or API keys; it is deliberately not persisted and disappears
/// with the process.
class AgentEvidenceCache {
  AgentEvidenceCache({this.maxEntries = 2}) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashMap<String, AgentEvidenceBundle> _entries =
      LinkedHashMap<String, AgentEvidenceBundle>();

  int get length => _entries.length;

  AgentEvidenceBundle? get(String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void put(String key, AgentEvidenceBundle evidence) {
    _entries.remove(key);
    _entries[key] = evidence;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

/// Text-only evidence cache key.
///
/// Profile, provider, answer language and strict/loose mode are intentionally
/// excluded: they change the prompt, not the OCR/token/lookup evidence. Images
/// are excluded for now because their identity requires a file-stat key.
String? agentEvidenceCacheKey(AgentRunRequest request, AgentLimits limits) {
  if (request.images.isNotEmpty) return null;
  final text = request.userText.trim();
  if (text.isEmpty) return null;
  final dictionaryPart = request.dictionaries
      .map(
        (DictionaryInfo dictionary) =>
            '${dictionary.id}\u0000${dictionary.order}\u0000'
            '${dictionary.title}\u0000${dictionary.mdxPath}',
      )
      .join('\u0001');
  final source = <String>[
    text,
    request.context.trim(),
    dictionaryPart,
    request.unidicPath.trim(),
    '${limits.hashCode}',
  ].join('\u0002');
  return sha256.convert(utf8.encode(source)).toString();
}
