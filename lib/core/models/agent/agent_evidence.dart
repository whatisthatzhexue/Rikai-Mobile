import 'agent_json.dart';

/// One UniDic token in the evidence bundle.
class AgentTokenEvidence {
  const AgentTokenEvidence({
    required this.id,
    required this.surface,
    required this.start,
    required this.end,
    this.reading = '',
    this.lemma = '',
    this.pos = '',
    this.content = false,
    this.lookupCandidates = const <String>[],
    this.citationIds = const <String>[],
  });

  final String id;
  final String surface;
  final String reading;
  final String lemma;
  final String pos;
  final int start;
  final int end;
  final bool content;
  final List<String> lookupCandidates;
  final List<String> citationIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'surface': surface,
    if (reading.isNotEmpty) 'reading': reading,
    if (lemma.isNotEmpty) 'lemma': lemma,
    if (pos.isNotEmpty) 'pos': pos,
    'start': start,
    'end': end,
    'content': content,
    if (lookupCandidates.isNotEmpty) 'lookup_candidates': lookupCandidates,
    if (citationIds.isNotEmpty) 'citation_ids': citationIds,
  };

  factory AgentTokenEvidence.fromJson(Map<String, Object?> json) {
    return AgentTokenEvidence(
      id: agentString(json['id']),
      surface: agentString(json['surface']),
      reading: agentString(json['reading']),
      lemma: agentString(json['lemma']),
      pos: agentString(json['pos']),
      start: agentInt(json['start']),
      end: agentInt(json['end']),
      content: agentBool(json['content']),
      lookupCandidates: agentStringList(json['lookup_candidates']),
      citationIds: agentStringList(json['citation_ids']),
    );
  }
}

/// A matched grammar pattern spanning one or more tokens.
class AgentGrammarPatternEvidence {
  const AgentGrammarPatternEvidence({
    required this.id,
    required this.surface,
    required this.tokenIds,
    required this.start,
    required this.end,
    this.citationIds = const <String>[],
  });

  final String id;
  final String surface;
  final List<String> tokenIds;
  final int start;
  final int end;
  final List<String> citationIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'surface': surface,
    'token_ids': tokenIds,
    'start': start,
    'end': end,
    if (citationIds.isNotEmpty) 'citation_ids': citationIds,
  };

  factory AgentGrammarPatternEvidence.fromJson(Map<String, Object?> json) {
    return AgentGrammarPatternEvidence(
      id: agentString(json['id']),
      surface: agentString(json['surface']),
      tokenIds: agentStringList(json['token_ids']),
      start: agentInt(json['start']),
      end: agentInt(json['end']),
      citationIds: agentStringList(json['citation_ids']),
    );
  }
}

/// A real dictionary entry reference issued by the orchestrator.
class AgentCitation {
  const AgentCitation({
    required this.id,
    required this.kind,
    required this.dictionaryId,
    required this.dictionaryTitle,
    required this.dictionaryOrder,
    required this.entryKey,
    required this.headword,
    required this.snippet,
    required this.toolCallId,
    this.matchedKey = '',
  });

  final String id;
  final String kind;
  final String dictionaryId;
  final String dictionaryTitle;
  final int dictionaryOrder;
  final String entryKey;
  final String matchedKey;
  final String headword;
  final String snippet;
  final String toolCallId;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'dictionary_id': dictionaryId,
    'dictionary_title': dictionaryTitle,
    'dictionary_order': dictionaryOrder,
    'entry_key': entryKey,
    if (matchedKey.isNotEmpty) 'matched_key': matchedKey,
    'headword': headword,
    'snippet': snippet,
    'tool_call_id': toolCallId,
  };

  factory AgentCitation.fromJson(Map<String, Object?> json) {
    return AgentCitation(
      id: agentString(json['id']),
      kind: agentString(json['kind'], 'mdict'),
      dictionaryId: agentString(json['dictionary_id']),
      dictionaryTitle: agentString(json['dictionary_title']),
      dictionaryOrder: agentInt(json['dictionary_order']),
      entryKey: agentString(json['entry_key']),
      matchedKey: agentString(json['matched_key']),
      headword: agentString(json['headword']),
      snippet: agentString(json['snippet']),
      toolCallId: agentString(json['tool_call_id']),
    );
  }
}

/// Token evidence for one source (image OCR or user text).
class AgentSourceEvidence {
  const AgentSourceEvidence({
    required this.id,
    required this.kind,
    required this.text,
    this.tokens = const <AgentTokenEvidence>[],
  });

  final String id;
  final String kind;
  final String text;
  final List<AgentTokenEvidence> tokens;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'text': text,
    'tokens': tokens.map((token) => token.toJson()).toList(),
  };

  factory AgentSourceEvidence.fromJson(Map<String, Object?> json) {
    final rawTokens = json['tokens'];
    return AgentSourceEvidence(
      id: agentString(json['id']),
      kind: agentString(json['kind']),
      text: agentString(json['text']),
      tokens: rawTokens is List
          ? rawTokens
                .whereType<Map>()
                .map(
                  (value) => AgentTokenEvidence.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentTokenEvidence>[],
    );
  }
}

/// A dictionary that failed during evidence collection. Other dictionaries in
/// the run keep working; the UI and the model are told the result is partial.
class AgentEvidenceDictionaryIssue {
  const AgentEvidenceDictionaryIssue({
    required this.dictionaryId,
    required this.dictionaryTitle,
    required this.code,
    required this.message,
  });

  final String dictionaryId;
  final String dictionaryTitle;
  final String code;
  final String message;

  Map<String, Object?> toJson() => {
    'dictionary_id': dictionaryId,
    'dictionary_title': dictionaryTitle,
    'code': code,
    'message': message,
  };

  factory AgentEvidenceDictionaryIssue.fromJson(Map<String, Object?> json) {
    return AgentEvidenceDictionaryIssue(
      dictionaryId: agentString(json['dictionary_id']),
      dictionaryTitle: agentString(json['dictionary_title']),
      code: agentString(json['code']),
      message: agentString(json['message']),
    );
  }
}

/// Counters and limits for one evidence run.
class AgentEvidenceBudget {
  const AgentEvidenceBudget({
    this.sourceChars = 0,
    this.uniqueTargets = 0,
    this.citations = 0,
    this.maxTargets = 120,
    this.maxCitations = 60,
  });

  final int sourceChars;
  final int uniqueTargets;
  final int citations;
  final int maxTargets;
  final int maxCitations;

  Map<String, Object?> toJson() => {
    'source_chars': sourceChars,
    'unique_targets': uniqueTargets,
    'citations': citations,
    'max_targets': maxTargets,
    'max_citations': maxCitations,
  };

  factory AgentEvidenceBudget.fromJson(Map<String, Object?> json) {
    return AgentEvidenceBudget(
      sourceChars: agentInt(json['source_chars']),
      uniqueTargets: agentInt(json['unique_targets']),
      citations: agentInt(json['citations']),
      maxTargets: agentInt(json['max_targets'], 120),
      maxCitations: agentInt(json['max_citations'], 60),
    );
  }
}

/// The complete evidence bundle sent to the model.
class AgentEvidenceBundle {
  const AgentEvidenceBundle({
    required this.sources,
    this.patterns = const <AgentGrammarPatternEvidence>[],
    this.citations = const <AgentCitation>[],
    this.truncated = false,
    this.structureUnavailable = false,
    this.dictionaryIssues = const <AgentEvidenceDictionaryIssue>[],
    this.budget = const AgentEvidenceBudget(),
  });

  static const String schema = 'rikai.agent.evidence.v1';

  final List<AgentSourceEvidence> sources;
  final List<AgentGrammarPatternEvidence> patterns;
  final List<AgentCitation> citations;
  final bool truncated;

  /// True when UniDic is not configured or tokenization failed. The run may
  /// still translate and cite dictionaries, but must not claim structural
  /// (token/grammar) analysis.
  final bool structureUnavailable;
  final List<AgentEvidenceDictionaryIssue> dictionaryIssues;
  final AgentEvidenceBudget budget;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'sources': sources.map((source) => source.toJson()).toList(),
    if (patterns.isNotEmpty)
      'patterns': patterns.map((pattern) => pattern.toJson()).toList(),
    'citations': citations.map((citation) => citation.toJson()).toList(),
    'truncated': truncated,
    'structure_unavailable': structureUnavailable,
    if (dictionaryIssues.isNotEmpty)
      'dictionary_issues': dictionaryIssues
          .map((issue) => issue.toJson())
          .toList(),
    'budget': budget.toJson(),
  };

  factory AgentEvidenceBundle.fromJson(Map<String, Object?> json) {
    final rawSources = json['sources'];
    final rawPatterns = json['patterns'];
    final rawCitations = json['citations'];
    final rawIssues = json['dictionary_issues'];
    return AgentEvidenceBundle(
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (value) => AgentSourceEvidence.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentSourceEvidence>[],
      patterns: rawPatterns is List
          ? rawPatterns
                .whereType<Map>()
                .map(
                  (value) => AgentGrammarPatternEvidence.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentGrammarPatternEvidence>[],
      citations: rawCitations is List
          ? rawCitations
                .whereType<Map>()
                .map(
                  (value) => AgentCitation.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentCitation>[],
      truncated: agentBool(json['truncated']),
      structureUnavailable: agentBool(json['structure_unavailable']),
      dictionaryIssues: rawIssues is List
          ? rawIssues
                .whereType<Map>()
                .map(
                  (value) => AgentEvidenceDictionaryIssue.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentEvidenceDictionaryIssue>[],
      budget: AgentEvidenceBudget.fromJson(agentMap(json['budget'])),
    );
  }
}
