import 'agent_json.dart';

/// How a claim is grounded. Strict mode uses this to enforce citations.
enum AgentEpistemic {
  dictionaryFact('dictionary_fact'),
  structuralAnalysis('structural_analysis'),
  contextInference('context_inference'),
  translation('translation');

  const AgentEpistemic(this.wireName);

  final String wireName;

  static AgentEpistemic fromWire(Object? value) {
    for (final item in AgentEpistemic.values) {
      if (item.wireName == value) return item;
    }
    return AgentEpistemic.contextInference;
  }
}

/// A translated segment. The label is always “模型译文”.
class AgentTranslation {
  const AgentTranslation({
    required this.quoteId,
    required this.text,
    this.label = expectedLabel,
    this.citationIds = const <String>[],
  });

  static const String expectedLabel = '模型译文';

  final String quoteId;
  final String text;
  final String label;
  final List<String> citationIds;

  Map<String, Object?> toJson() => {
    'quote_id': quoteId,
    'text': text,
    'label': label,
    if (citationIds.isNotEmpty) 'citation_ids': citationIds,
  };

  factory AgentTranslation.fromJson(Map<String, Object?> json) {
    return AgentTranslation(
      quoteId: agentString(json['quote_id']),
      text: agentString(json['text']),
      label: agentString(json['label'], expectedLabel),
      citationIds: agentStringList(json['citation_ids']),
    );
  }
}

class AgentWordNote {
  const AgentWordNote({
    required this.tokenId,
    required this.surface,
    required this.sense,
    this.reading = '',
    this.citationIds = const <String>[],
  });

  final String tokenId;
  final String surface;
  final String reading;
  final String sense;
  final List<String> citationIds;

  Map<String, Object?> toJson() => {
    'token_id': tokenId,
    'surface': surface,
    if (reading.isNotEmpty) 'reading': reading,
    'sense': sense,
    if (citationIds.isNotEmpty) 'citation_ids': citationIds,
  };

  factory AgentWordNote.fromJson(Map<String, Object?> json) {
    return AgentWordNote(
      tokenId: agentString(json['token_id']),
      surface: agentString(json['surface']),
      reading: agentString(json['reading']),
      sense: agentString(json['sense']),
      citationIds: agentStringList(json['citation_ids']),
    );
  }
}

class AgentGrammarNote {
  const AgentGrammarNote({
    required this.patternId,
    required this.explanation,
    this.citationIds = const <String>[],
  });

  final String patternId;
  final String explanation;
  final List<String> citationIds;

  Map<String, Object?> toJson() => {
    'pattern_id': patternId,
    'explanation': explanation,
    if (citationIds.isNotEmpty) 'citation_ids': citationIds,
  };

  factory AgentGrammarNote.fromJson(Map<String, Object?> json) {
    return AgentGrammarNote(
      patternId: agentString(json['pattern_id']),
      explanation: agentString(json['explanation']),
      citationIds: agentStringList(json['citation_ids']),
    );
  }
}

/// One analyzed source segment. [literal] is filled by the orchestrator.
class AgentSegment {
  const AgentSegment({
    required this.id,
    required this.quoteId,
    required this.interpretation,
    required this.epistemic,
    this.literal = '',
    this.wordNotes = const <AgentWordNote>[],
    this.grammarNotes = const <AgentGrammarNote>[],
    this.confidence = 0,
  });

  final String id;
  final String quoteId;
  final String literal;
  final String interpretation;
  final List<AgentWordNote> wordNotes;
  final List<AgentGrammarNote> grammarNotes;
  final AgentEpistemic epistemic;
  final double confidence;

  Map<String, Object?> toJson() => {
    'id': id,
    'quote_id': quoteId,
    if (literal.isNotEmpty) 'literal': literal,
    'interpretation': interpretation,
    if (wordNotes.isNotEmpty)
      'word_notes': wordNotes.map((note) => note.toJson()).toList(),
    if (grammarNotes.isNotEmpty)
      'grammar_notes': grammarNotes.map((note) => note.toJson()).toList(),
    'epistemic': epistemic.wireName,
    'confidence': confidence,
  };

  factory AgentSegment.fromJson(Map<String, Object?> json) {
    final rawWords = json['word_notes'];
    final rawGrammar = json['grammar_notes'];
    return AgentSegment(
      id: agentString(json['id']),
      quoteId: agentString(json['quote_id']),
      literal: agentString(json['literal']),
      interpretation: agentString(json['interpretation']),
      wordNotes: rawWords is List
          ? rawWords
                .whereType<Map>()
                .map(
                  (value) => AgentWordNote.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentWordNote>[],
      grammarNotes: rawGrammar is List
          ? rawGrammar
                .whereType<Map>()
                .map(
                  (value) => AgentGrammarNote.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentGrammarNote>[],
      epistemic: AgentEpistemic.fromWire(json['epistemic']),
      confidence: agentDouble(json['confidence']),
    );
  }
}

class AgentInterpretation {
  const AgentInterpretation({
    required this.id,
    required this.label,
    required this.meaning,
    required this.confidence,
    this.citationIds = const <String>[],
  });

  final String id;
  final String label;
  final String meaning;
  final double confidence;
  final List<String> citationIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'meaning': meaning,
    'confidence': confidence,
    if (citationIds.isNotEmpty) 'citation_ids': citationIds,
  };

  factory AgentInterpretation.fromJson(Map<String, Object?> json) {
    return AgentInterpretation(
      id: agentString(json['id']),
      label: agentString(json['label']),
      meaning: agentString(json['meaning']),
      confidence: agentDouble(json['confidence']),
      citationIds: agentStringList(json['citation_ids']),
    );
  }
}

class AgentUnresolved {
  const AgentUnresolved({required this.quoteId, required this.reason});

  final String quoteId;
  final String reason;

  Map<String, Object?> toJson() => {'quote_id': quoteId, 'reason': reason};

  factory AgentUnresolved.fromJson(Map<String, Object?> json) {
    return AgentUnresolved(
      quoteId: agentString(json['quote_id']),
      reason: agentString(json['reason']),
    );
  }
}

class AgentModelSupplement {
  const AgentModelSupplement({required this.text});

  static const String label = '模型补充';

  final String text;

  Map<String, Object?> toJson() => {'text': text, 'label': label};

  factory AgentModelSupplement.fromJson(Map<String, Object?> json) {
    return AgentModelSupplement(text: agentString(json['text']));
  }
}

/// Structured output of the reasoning stage.
class AgentAnalysis {
  const AgentAnalysis({
    required this.sourceId,
    this.translation = const <AgentTranslation>[],
    this.segments = const <AgentSegment>[],
    this.interpretations = const <AgentInterpretation>[],
    this.unresolved = const <AgentUnresolved>[],
    this.citationsUsed = const <String>[],
    this.modelSupplements = const <AgentModelSupplement>[],
  });

  static const String schema = 'rikai.agent.analysis.v1';

  final String sourceId;
  final List<AgentTranslation> translation;
  final List<AgentSegment> segments;
  final List<AgentInterpretation> interpretations;
  final List<AgentUnresolved> unresolved;
  final List<String> citationsUsed;
  final List<AgentModelSupplement> modelSupplements;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'source_id': sourceId,
    'translation': translation.map((item) => item.toJson()).toList(),
    'segments': segments.map((item) => item.toJson()).toList(),
    if (interpretations.isNotEmpty)
      'interpretations': interpretations.map((item) => item.toJson()).toList(),
    if (unresolved.isNotEmpty)
      'unresolved': unresolved.map((item) => item.toJson()).toList(),
    if (citationsUsed.isNotEmpty) 'citations_used': citationsUsed,
    if (modelSupplements.isNotEmpty)
      'model_supplements': modelSupplements
          .map((item) => item.toJson())
          .toList(),
  };

  factory AgentAnalysis.fromJson(Map<String, Object?> json) {
    final rawTranslation = json['translation'];
    final rawSegments = json['segments'];
    final rawInterpretations = json['interpretations'];
    final rawUnresolved = json['unresolved'];
    final rawSupplements = json['model_supplements'];
    return AgentAnalysis(
      sourceId: agentString(json['source_id']),
      translation: rawTranslation is List
          ? rawTranslation
                .whereType<Map>()
                .map(
                  (value) => AgentTranslation.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentTranslation>[],
      segments: rawSegments is List
          ? rawSegments
                .whereType<Map>()
                .map(
                  (value) => AgentSegment.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentSegment>[],
      interpretations: rawInterpretations is List
          ? rawInterpretations
                .whereType<Map>()
                .map(
                  (value) => AgentInterpretation.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentInterpretation>[],
      unresolved: rawUnresolved is List
          ? rawUnresolved
                .whereType<Map>()
                .map(
                  (value) => AgentUnresolved.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentUnresolved>[],
      citationsUsed: agentStringList(json['citations_used']),
      modelSupplements: rawSupplements is List
          ? rawSupplements
                .whereType<Map>()
                .map(
                  (value) => AgentModelSupplement.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentModelSupplement>[],
    );
  }
}
