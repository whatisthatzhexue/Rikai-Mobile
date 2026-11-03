import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/utils/rich_text_tags.dart';
import 'tag_block_integrity.dart';

/// Parser-side weights for OPTION blocks. The model does not emit numbers;
/// multiple options are normalized by `normalizeAnalysis`/`salvageAnalysis`
/// into a distribution summing to 100%.
const double _optionCitedWeight = 0.7;
const double _optionUncitedWeight = 0.5;

const _analysisBlockTags = <String>{
  'TRANSLATION',
  'SEGMENT',
  'MEANING',
  'WORD',
  'GRAMMAR',
  'OPTION',
  'UNRESOLVED',
  'SUPPLEMENT',
};

final _noAnalysisTagPattern = RegExp(
  r'\[NO_ANALYSIS\b([^\]]*)\]',
  caseSensitive: false,
);

final _otherAnalysisTagPattern = RegExp(
  r'\[(?:TRANSLATION|SEGMENT|MEANING|WORD|GRAMMAR|OPTION|UNRESOLVED|'
  r'SUPPLEMENT)\b',
  caseSensitive: false,
);

/// Reports unbalanced or mis-nested analysis blocks. Parsing may still succeed
/// on a truncated response; callers use these errors to request repair.
List<String> analysisTagIntegrityErrors(String raw) {
  final errors = tagBlockIntegrityErrors(
    raw,
    blockTags: _analysisBlockTags,
    rootOnlyTags: const <String>{
      'TRANSLATION',
      'SEGMENT',
      'OPTION',
      'UNRESOLVED',
      'SUPPLEMENT',
    },
    requiredParent: const <String, String>{
      'MEANING': 'SEGMENT',
      'WORD': 'SEGMENT',
      'GRAMMAR': 'SEGMENT',
    },
    singleInParent: const <String>{'MEANING'},
  ).toList();
  if (!isWellFormedYomi(raw)) {
    errors.add('YOMI 标签必须成对且不能嵌套');
  }
  if (_noAnalysisTagPattern.hasMatch(raw) &&
      _otherAnalysisTagPattern.hasMatch(raw)) {
    errors.add('NO_ANALYSIS 不能与其他分析标签共存');
  }
  return List<String>.unmodifiable(errors);
}

/// Parses the flat, tag-delimited analysis format used by the new prompts.
///
/// The model only writes readable text and simple block tags; all claim types,
/// confidence values, segment ids and the source id are assigned here. This is
/// intentionally more forgiving than JSON under long inputs: a single missing
/// closing tag cannot invalidate the whole response, and unknown prose outside
/// tags is ignored.
AgentAnalysis? parseTaggedAnalysis(
  String raw, {
  required String sourceId,
  AgentLimits limits = AgentLimits.standard,
}) {
  final noAnalysisReason = _parseNoAnalysisReason(raw);
  if (noAnalysisReason != null) {
    if (_otherAnalysisTagPattern.hasMatch(raw)) return null;
    return AgentAnalysis(
      sourceId: sourceId,
      noAnalysisReason: noAnalysisReason,
    );
  }

  final translations = <AgentTranslation>[];
  final translationPattern = RegExp(
    r'\[TRANSLATION\b([^\]]*)\]([\s\S]*?)\[/TRANSLATION\]',
    caseSensitive: false,
  );
  for (final match in translationPattern.allMatches(raw)) {
    final attrs = match.group(1) ?? '';
    final text = _cleanBody(match.group(2) ?? '');
    if (text.isEmpty) continue;
    final quoteId = _attrAny(attrs, const <String>['quote', 'quote_id']);
    if (quoteId.isEmpty) continue;
    translations.add(
      AgentTranslation(
        quoteId: quoteId,
        text: text,
        citationIds: _citationIds(_attr(attrs, 'citations')),
      ),
    );
  }

  final segments = <AgentSegment>[];
  final segmentPattern = RegExp(
    r'\[SEGMENT\b([^\]]*)\]([\s\S]*?)\[/SEGMENT\]',
    caseSensitive: false,
  );
  var segmentIndex = 0;
  var truncated = false;
  final segmentCounts = <String, int>{};
  for (final match in segmentPattern.allMatches(raw)) {
    segmentIndex++;
    final attrs = match.group(1) ?? '';
    final body = match.group(2) ?? '';
    final quoteId = _attrAny(attrs, const <String>['quote', 'quote_id']);
    final declaredType = _attr(attrs, 'type');
    final effectiveType = declaredType.isEmpty
        ? _leakedType(body)
        : declaredType;
    if (segments.length >= limits.maxSegments) {
      truncated = true;
      break;
    }
    if (quoteId.isNotEmpty) {
      final segmentKey = '$quoteId\u0000${effectiveType.trim().toLowerCase()}';
      final count = segmentCounts[segmentKey] ?? 0;
      if (count >= limits.maxSegmentsPerQuotePerType) {
        truncated = true;
        continue;
      }
      segmentCounts[segmentKey] = count + 1;
    }
    final meaningMatch = RegExp(
      r'\[MEANING\]([\s\S]*?)\[/MEANING\]',
      caseSensitive: false,
    ).firstMatch(body);
    var interpretation = _cleanBody(meaningMatch?.group(1) ?? '');
    if (interpretation.isEmpty) {
      interpretation = _cleanBody(
        body
            .replaceAll(
              RegExp(
                r'\[WORD\b[^\]]*\][\s\S]*?\[/WORD\]',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(
              RegExp(
                r'\[GRAMMAR\b[^\]]*\][\s\S]*?\[/GRAMMAR\]',
                caseSensitive: false,
              ),
              '',
            ),
      );
    }
    if (quoteId.isEmpty || interpretation.isEmpty) continue;

    final wordNotes = <AgentWordNote>[];
    final wordPattern = RegExp(
      r'\[WORD\b([^\]]*)\]([\s\S]*?)\[/WORD\]',
      caseSensitive: false,
    );
    for (final word in wordPattern.allMatches(body)) {
      final fields = (word.group(2) ?? '')
          .split(RegExp(r'[|｜]'))
          .map((value) => value.trim())
          .toList(growable: false);
      if (fields.isEmpty || fields.first.isEmpty) continue;
      final String surface;
      final String reading;
      final String sense;
      final List<String> citations;
      if (fields.length >= 4) {
        surface = fields[0];
        reading = fields[1];
        sense = fields[2];
        citations = _citationIds(fields[3]);
      } else if (fields.length == 3) {
        surface = fields[0];
        reading = '';
        sense = fields[1];
        citations = _citationIds(fields[2]);
      } else if (fields.length == 2) {
        surface = fields[0];
        reading = '';
        sense = fields[1];
        citations = _citationIds(_attr(word.group(1) ?? '', 'citations'));
      } else {
        continue;
      }
      final tokenId = _attrAny(word.group(1) ?? '', const <String>[
        'id',
        'token_id',
      ]);
      wordNotes.add(
        AgentWordNote(
          tokenId: tokenId,
          surface: surface,
          reading: reading,
          sense: _cleanBody(sense),
          citationIds: citations,
        ),
      );
    }

    final grammarNotes = <AgentGrammarNote>[];
    final grammarPattern = RegExp(
      r'\[GRAMMAR\b([^\]]*)\]([\s\S]*?)\[/GRAMMAR\]',
      caseSensitive: false,
    );
    for (final grammar in grammarPattern.allMatches(body)) {
      final fields = (grammar.group(2) ?? '')
          .split(RegExp(r'[|｜]'))
          .map((value) => value.trim())
          .toList(growable: false);
      if (fields.isEmpty || fields.first.isEmpty) continue;
      grammarNotes.add(
        AgentGrammarNote(
          patternId: _attrAny(grammar.group(1) ?? '', const <String>[
            'id',
            'pattern_id',
          ]),
          explanation: _cleanBody(fields.first),
          citationIds: _citationIds(
            fields.length >= 2
                ? fields[1]
                : _attr(grammar.group(1) ?? '', 'citations'),
          ),
        ),
      );
    }

    final boundedWordNotes = wordNotes.length > limits.maxNotesPerSegment
        ? wordNotes.take(limits.maxNotesPerSegment).toList(growable: false)
        : wordNotes;
    final boundedGrammarNotes = grammarNotes.length > limits.maxNotesPerSegment
        ? grammarNotes.take(limits.maxNotesPerSegment).toList(growable: false)
        : grammarNotes;
    if (boundedWordNotes.length != wordNotes.length ||
        boundedGrammarNotes.length != grammarNotes.length) {
      truncated = true;
    }
    segments.add(
      AgentSegment(
        id: 'seg-$segmentIndex',
        quoteId: quoteId,
        interpretation: interpretation,
        epistemic: _epistemic(effectiveType),
        wordNotes: boundedWordNotes,
        grammarNotes: boundedGrammarNotes,
        confidence: _confidenceFor(effectiveType),
      ),
    );
  }

  final interpretations = <AgentInterpretation>[];
  final optionPattern = RegExp(
    r'\[OPTION\b([^\]]*)\]([\s\S]*?)\[/OPTION\]',
    caseSensitive: false,
  );
  var optionIndex = 0;
  for (final match in optionPattern.allMatches(raw)) {
    optionIndex++;
    if (interpretations.length >= limits.maxOptionsPerRun) {
      truncated = true;
      break;
    }
    final meaning = _cleanBody(match.group(2) ?? '');
    if (meaning.isEmpty) continue;
    final attrs = match.group(1) ?? '';
    final citations = _citationIds(_attr(attrs, 'citations'));
    interpretations.add(
      AgentInterpretation(
        id: _attr(attrs, 'id').isEmpty ? 'i$optionIndex' : _attr(attrs, 'id'),
        label: _attr(attrs, 'label').isEmpty
            ? String.fromCharCode(64 + optionIndex)
            : _attr(attrs, 'label'),
        meaning: meaning,
        confidence: citations.isEmpty
            ? _optionUncitedWeight
            : _optionCitedWeight,
        citationIds: citations,
      ),
    );
  }

  final unresolved = <AgentUnresolved>[];
  final unresolvedPattern = RegExp(
    r'\[UNRESOLVED\b([^\]]*)\]([\s\S]*?)\[/UNRESOLVED\]',
    caseSensitive: false,
  );
  for (final match in unresolvedPattern.allMatches(raw)) {
    final reason = _cleanBody(match.group(2) ?? '');
    if (reason.isEmpty) continue;
    unresolved.add(
      AgentUnresolved(
        quoteId: _attrAny(match.group(1) ?? '', const <String>[
          'quote',
          'quote_id',
        ]),
        reason: reason,
      ),
    );
  }

  final supplements = <AgentModelSupplement>[];
  final supplementPattern = RegExp(
    r'\[SUPPLEMENT\]([\s\S]*?)\[/SUPPLEMENT\]',
    caseSensitive: false,
  );
  for (final match in supplementPattern.allMatches(raw)) {
    final text = _cleanBody(match.group(1) ?? '');
    if (text.isNotEmpty) supplements.add(AgentModelSupplement(text: text));
  }

  if (translations.isEmpty || segments.isEmpty) return null;
  final usedCitations = <String>{
    for (final translation in translations) ...translation.citationIds,
    for (final segment in segments) ...{
      for (final note in segment.wordNotes) ...note.citationIds,
      for (final note in segment.grammarNotes) ...note.citationIds,
    },
    for (final interpretation in interpretations) ...interpretation.citationIds,
  };
  return AgentAnalysis(
    sourceId: sourceId,
    translation: translations,
    segments: segments,
    interpretations: interpretations,
    unresolved: unresolved,
    citationsUsed: usedCitations.toList(growable: false),
    modelSupplements: supplements,
    truncated: truncated,
  );
}

/// Parses `[NO_ANALYSIS reason="..."]` or the block form
/// `[NO_ANALYSIS]reason[/NO_ANALYSIS]`. Returns null when the tag is absent.
String? _parseNoAnalysisReason(String raw) {
  final block = RegExp(
    r'\[NO_ANALYSIS\b([^\]]*)\]([\s\S]*?)\[/NO_ANALYSIS\]',
    caseSensitive: false,
  ).firstMatch(raw);
  if (block != null) {
    final attrReason = _attr(block.group(1) ?? '', 'reason').trim();
    final bodyReason = _cleanBody(block.group(2) ?? '').trim();
    final reason = attrReason.isNotEmpty ? attrReason : bodyReason;
    return _boundedNoAnalysisReason(reason);
  }
  final tag = _noAnalysisTagPattern.firstMatch(raw);
  if (tag == null) return null;
  return _boundedNoAnalysisReason(_attr(tag.group(1) ?? '', 'reason'));
}

String _boundedNoAnalysisReason(String raw) {
  final reason = raw.trim();
  if (reason.isEmpty) return '模型无法可靠分析这段文本';
  return reason.length <= 500 ? reason : reason.substring(0, 500);
}

String _attrAny(String attrs, List<String> names) {
  for (final name in names) {
    final value = _attr(attrs, name);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _attr(String attrs, String name) {
  final pattern = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s]+))',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(attrs);
  if (match == null) return '';
  return (match.group(1) ?? match.group(2) ?? match.group(3) ?? '').trim();
}

List<String> _citationIds(String raw) {
  return <String>[
    for (final value in raw.split(RegExp(r'[,，\s]+')))
      if (value.trim().isNotEmpty) value.trim(),
  ];
}

String _leakedType(String body) {
  final lower = body.toLowerCase();
  if (lower.contains('dictionary_fact')) return 'dictionary_fact';
  if (lower.contains('structural_analysis')) return 'structural_analysis';
  if (lower.contains('context_inference')) return 'context_inference';
  return '';
}

AgentEpistemic _epistemic(String type) {
  return switch (type.trim().toLowerCase()) {
    'fact' ||
    'dictionary_fact' ||
    'dictionary-fact' => AgentEpistemic.dictionaryFact,
    'structure' ||
    'structural_analysis' ||
    'structural-analysis' => AgentEpistemic.structuralAnalysis,
    'translation' => AgentEpistemic.translation,
    _ => AgentEpistemic.contextInference,
  };
}

double _confidenceFor(String type) {
  return switch (_epistemic(type)) {
    AgentEpistemic.dictionaryFact => 0.95,
    AgentEpistemic.structuralAnalysis => 0.9,
    AgentEpistemic.contextInference => 0.6,
    AgentEpistemic.translation => 0.95,
  };
}

/// Removes internal markers/probabilities that the model may leak into prose.
/// The renderer derives the real type/confidence from the block tag.
String _cleanBody(String raw) {
  return raw
      .replaceAll(
        RegExp(r'[（(]\s*\d{1,3}(?:\.\d+)?\s*%\s*[）)]', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(
          r'\b(?:context_inference|dictionary_fact|structural_analysis|'
          r'model_supplement)\b',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'\bconfidence\s*[:：]\s*[\d.]+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'置信度\s*[:：]?\s*\d+(?:\.\d+)?\s*%?'), '')
      .replaceAll(RegExp(r'\[source-\d+\]'), '')
      .replaceAll(
        RegExp(
          r'\[/?(?:MEANING|SEGMENT|WORD|GRAMMAR|TRANSLATION|OPTION|'
          r'UNRESOLVED|SUPPLEMENT)\b[^\]]*\]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}
