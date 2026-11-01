import 'agent_json.dart';

enum AgentCoverageVerdict {
  sufficient,
  missing;

  String get wireName => name;

  static AgentCoverageVerdict fromWire(Object? value) {
    return value == 'missing'
        ? AgentCoverageVerdict.missing
        : AgentCoverageVerdict.sufficient;
  }
}

enum AgentCoverageKind {
  word,
  grammar,
  sense,
  usage,
  reading,
  example,
  context;

  String get wireName => name;

  static AgentCoverageKind fromWire(Object? value) {
    for (final item in AgentCoverageKind.values) {
      if (item.wireName == value) return item;
    }
    return AgentCoverageKind.word;
  }
}

class AgentCoverageMissing {
  const AgentCoverageMissing({
    required this.kind,
    required this.query,
    required this.sourceRefs,
    required this.reason,
    this.priority = 3,
  });

  final AgentCoverageKind kind;
  final String query;
  final List<String> sourceRefs;
  final String reason;
  final int priority;

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    'query': query,
    'source_refs': sourceRefs,
    'reason': reason,
    'priority': priority,
  };

  factory AgentCoverageMissing.fromJson(Map<String, Object?> json) {
    return AgentCoverageMissing(
      kind: AgentCoverageKind.fromWire(json['kind']),
      query: agentString(json['query']).trim(),
      sourceRefs: agentStringList(json['source_refs']),
      reason: agentString(json['reason']).trim(),
      priority: agentInt(json['priority'], 3).clamp(1, 5),
    );
  }
}

class AgentCoverageDuplicateGroup {
  const AgentCoverageDuplicateGroup({
    required this.dictionaryId,
    required this.keepEntryKey,
    required this.removeEntryKeys,
    required this.reason,
  });

  final String dictionaryId;
  final String keepEntryKey;
  final List<String> removeEntryKeys;
  final String reason;

  Map<String, Object?> toJson() => {
    'dictionary_id': dictionaryId,
    'keep_entry_key': keepEntryKey,
    'remove_entry_keys': removeEntryKeys,
    'reason': reason,
  };

  factory AgentCoverageDuplicateGroup.fromJson(Map<String, Object?> json) {
    return AgentCoverageDuplicateGroup(
      dictionaryId: agentString(json['dictionary_id']).trim(),
      keepEntryKey: agentString(json['keep_entry_key']).trim(),
      removeEntryKeys: <String>[
        for (final key in agentStringList(json['remove_entry_keys']))
          if (key.trim().isNotEmpty) key.trim(),
      ],
      reason: agentString(json['reason']).trim(),
    );
  }
}

class AgentCoverageReview {
  const AgentCoverageReview({
    required this.sourceId,
    required this.verdict,
    required this.missing,
    required this.duplicateGroups,
    this.notes = '',
  });

  static const String schema = 'rikai.agent.coverage.v1';

  final String sourceId;
  final AgentCoverageVerdict verdict;
  final List<AgentCoverageMissing> missing;
  final List<AgentCoverageDuplicateGroup> duplicateGroups;
  final String notes;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'source_id': sourceId,
    'verdict': verdict.wireName,
    'missing': missing.map((item) => item.toJson()).toList(),
    'duplicate_groups': duplicateGroups.map((group) => group.toJson()).toList(),
    'notes': notes,
  };

  factory AgentCoverageReview.fromJson(Map<String, Object?> json) {
    final rawMissing = json['missing'];
    final rawGroups = json['duplicate_groups'];
    return AgentCoverageReview(
      sourceId: agentString(json['source_id']).trim(),
      verdict: AgentCoverageVerdict.fromWire(json['verdict']),
      missing: rawMissing is List
          ? rawMissing
                .whereType<Map>()
                .map(
                  (value) => AgentCoverageMissing.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentCoverageMissing>[],
      duplicateGroups: rawGroups is List
          ? rawGroups
                .whereType<Map>()
                .map(
                  (value) => AgentCoverageDuplicateGroup.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentCoverageDuplicateGroup>[],
      notes: agentString(json['notes']).trim(),
    );
  }
}
