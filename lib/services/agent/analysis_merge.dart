import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_limits.dart';

/// Merges one analysis per dictionary into the normal single analysis shape.
///
/// The merge is deterministic and follows user dictionary order:
/// - one translation per quote (first non-empty wins);
/// - one segment per quote + epistemic type, with word/grammar notes combined
///   and de-duplicated;
/// - options de-duplicated by meaning and re-labelled A/B/C...;
/// - unresolved items and supplements de-duplicated;
/// - ids re-indexed so the UI never sees duplicate s1/i1 ids.
AgentAnalysis mergeDictionaryAnalyses(
  Iterable<AgentAnalysis> analyses, {
  AgentLimits limits = AgentLimits.standard,
}) {
  final inputs = analyses.toList(growable: false);
  if (inputs.isEmpty) {
    return const AgentAnalysis(sourceId: '', noAnalysisReason: '模型没有返回可解析的分析');
  }

  final translations = <String, AgentTranslation>{};
  final segments = <String, AgentSegment>{};
  final segmentOrder = <String>[];
  final interpretations = <AgentInterpretation>[];
  final interpretationKeys = <String>{};
  final unresolved = <AgentUnresolved>[];
  final unresolvedKeys = <String>{};
  final supplements = <AgentModelSupplement>[];
  final supplementKeys = <String>{};
  final citationsUsed = <String>{};
  var truncated = false;
  var noAnalysisReason = '';

  for (final analysis in inputs) {
    for (final translation in analysis.translation) {
      if (translation.text.trim().isEmpty) continue;
      final existing = translations[translation.quoteId];
      if (existing == null || existing.text.trim().isEmpty) {
        translations[translation.quoteId] = translation;
      }
    }
    for (final segment in analysis.segments) {
      final key = '${segment.quoteId}\u0000${segment.epistemic.wireName}';
      final existing = segments[key];
      if (existing == null) {
        segments[key] = segment;
        segmentOrder.add(key);
        continue;
      }
      final wordNotes = _mergeWordNotes(existing.wordNotes, segment.wordNotes);
      final grammarNotes = _mergeGrammarNotes(
        existing.grammarNotes,
        segment.grammarNotes,
      );
      final noteTruncated =
          wordNotes.length > limits.maxNotesPerSegment ||
          grammarNotes.length > limits.maxNotesPerSegment;
      if (noteTruncated) truncated = true;
      segments[key] = AgentSegment(
        id: existing.id,
        quoteId: existing.quoteId,
        literal: existing.literal.isEmpty ? segment.literal : existing.literal,
        interpretation: existing.interpretation.isEmpty
            ? segment.interpretation
            : existing.interpretation,
        epistemic: existing.epistemic,
        confidence: existing.confidence >= segment.confidence
            ? existing.confidence
            : segment.confidence,
        wordNotes: wordNotes
            .take(limits.maxNotesPerSegment)
            .toList(growable: false),
        grammarNotes: grammarNotes
            .take(limits.maxNotesPerSegment)
            .toList(growable: false),
      );
    }
    for (final interpretation in analysis.interpretations) {
      final key = interpretation.meaning.trim().toLowerCase();
      if (key.isEmpty || !interpretationKeys.add(key)) continue;
      interpretations.add(interpretation);
    }
    for (final item in analysis.unresolved) {
      final key = '${item.quoteId}\u0000${item.reason.trim()}';
      if (!unresolvedKeys.add(key)) continue;
      unresolved.add(item);
    }
    for (final supplement in analysis.modelSupplements) {
      final key = supplement.text.trim();
      if (key.isEmpty || !supplementKeys.add(key)) continue;
      supplements.add(supplement);
    }
    citationsUsed.addAll(analysis.citationsUsed);
    truncated = truncated || analysis.truncated;
    if (noAnalysisReason.isEmpty) noAnalysisReason = analysis.noAnalysisReason;
  }

  final mergedSegments = <AgentSegment>[
    for (var index = 0; index < segmentOrder.length; index++)
      _withSegmentId(segments[segmentOrder[index]]!, 's${index + 1}'),
  ];
  final cappedSegments = mergedSegments
      .take(limits.maxSegments)
      .toList(growable: false);
  if (mergedSegments.length > cappedSegments.length) truncated = true;

  final cappedInterpretations = <AgentInterpretation>[
    for (var index = 0; index < interpretations.length; index++)
      AgentInterpretation(
        id: 'i${index + 1}',
        label: _optionLabel(index),
        meaning: interpretations[index].meaning,
        confidence: interpretations[index].confidence,
        citationIds: interpretations[index].citationIds,
      ),
  ].take(limits.maxOptionsPerRun).toList(growable: false);
  if (interpretations.length > cappedInterpretations.length) truncated = true;

  final hasContent =
      translations.isNotEmpty ||
      cappedSegments.isNotEmpty ||
      cappedInterpretations.isNotEmpty ||
      unresolved.isNotEmpty ||
      supplements.isNotEmpty;
  return AgentAnalysis(
    sourceId: inputs.first.sourceId,
    translation: List<AgentTranslation>.unmodifiable(translations.values),
    segments: List<AgentSegment>.unmodifiable(cappedSegments),
    interpretations: List<AgentInterpretation>.unmodifiable(
      cappedInterpretations,
    ),
    unresolved: List<AgentUnresolved>.unmodifiable(unresolved),
    citationsUsed: List<String>.unmodifiable(citationsUsed),
    modelSupplements: List<AgentModelSupplement>.unmodifiable(supplements),
    noAnalysisReason: hasContent ? '' : noAnalysisReason,
    truncated: truncated,
  );
}

List<AgentWordNote> _mergeWordNotes(
  List<AgentWordNote> first,
  List<AgentWordNote> second,
) {
  final result = <AgentWordNote>[];
  final keys = <String>{};
  for (final note in <AgentWordNote>[...first, ...second]) {
    final key =
        '${note.tokenId}\u0000${note.surface}\u0000${note.reading}\u0000'
        '${note.sense}\u0000${note.citationIds.join(',')}';
    if (keys.add(key)) result.add(note);
  }
  return result;
}

List<AgentGrammarNote> _mergeGrammarNotes(
  List<AgentGrammarNote> first,
  List<AgentGrammarNote> second,
) {
  final result = <AgentGrammarNote>[];
  final keys = <String>{};
  for (final note in <AgentGrammarNote>[...first, ...second]) {
    final key =
        '${note.patternId}\u0000${note.explanation}\u0000'
        '${note.citationIds.join(',')}';
    if (keys.add(key)) result.add(note);
  }
  return result;
}

AgentSegment _withSegmentId(AgentSegment segment, String id) {
  return AgentSegment(
    id: id,
    quoteId: segment.quoteId,
    literal: segment.literal,
    interpretation: segment.interpretation,
    epistemic: segment.epistemic,
    confidence: segment.confidence,
    wordNotes: segment.wordNotes,
    grammarNotes: segment.grammarNotes,
  );
}

String _optionLabel(int index) {
  const labels = <String>['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  return index < labels.length ? labels[index] : '${index + 1}';
}
