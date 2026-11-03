import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_quote.dart';

/// Normalizes model output before validation.
///
/// The model is allowed to select a quote, but it must not rewrite it. The
/// orchestrator owns `literal` and the set of valid grammar pattern IDs.
AgentAnalysis normalizeAnalysis({
  required AgentAnalysis analysis,
  required List<AgentQuoteRef> quotes,
  required AgentEvidenceBundle evidence,
}) {
  final quoteById = <String, AgentQuoteRef>{
    for (final quote in quotes) quote.id: quote,
  };
  final patternIds = evidence.patterns.map((pattern) => pattern.id).toSet();
  return AgentAnalysis(
    sourceId: analysis.sourceId,
    translation: analysis.translation,
    segments: <AgentSegment>[
      for (final segment in analysis.segments)
        AgentSegment(
          id: segment.id,
          quoteId: segment.quoteId,
          literal: quoteById[segment.quoteId]?.text ?? '',
          interpretation: segment.interpretation,
          wordNotes: segment.wordNotes,
          grammarNotes: segment.grammarNotes
              .where((note) => patternIds.contains(note.patternId))
              .toList(growable: false),
          epistemic: segment.epistemic,
          confidence: segment.confidence,
        ),
    ],
    interpretations: normalizeInterpretationConfidences(
      analysis.interpretations,
    ),
    unresolved: analysis.unresolved,
    citationsUsed: analysis.citationsUsed,
    modelSupplements: analysis.modelSupplements,
    noAnalysisReason: analysis.noAnalysisReason,
    truncated: analysis.truncated,
  );
}

/// Turns the parser's per-option heuristic weights into a probability
/// distribution when several alternative interpretations are present.
///
/// The model is explicitly told not to emit confidence values, so the parser
/// assigns a weak weight from citation presence. Showing those weights
/// directly makes two options both read "70%" and sum to 140%. Multiple
/// options are therefore normalized to integer percentages summing to 100;
/// a single option keeps its heuristic confidence because there is no
/// distribution to normalize. Values are stored as fractions so the UI and
/// Markdown renderer can multiply by 100 without another rounding rule.
List<AgentInterpretation> normalizeInterpretationConfidences(
  List<AgentInterpretation> interpretations,
) {
  if (interpretations.isEmpty) return const <AgentInterpretation>[];
  final clamped = <AgentInterpretation>[
    for (final item in interpretations)
      AgentInterpretation(
        id: item.id,
        label: item.label,
        meaning: item.meaning,
        confidence: item.confidence.isFinite
            ? item.confidence.clamp(0.0, 1.0).toDouble()
            : 0,
        citationIds: item.citationIds,
      ),
  ];
  if (clamped.length == 1) return clamped;

  final weights = <double>[for (final item in clamped) item.confidence];
  var total = weights.fold<double>(0, (sum, value) => sum + value);
  if (total <= 0) {
    for (var index = 0; index < weights.length; index++) {
      weights[index] = 1;
    }
    total = weights.length.toDouble();
  }

  final exact = <double>[for (final weight in weights) weight / total * 100];
  final percents = <int>[for (final value in exact) value.floor()];
  var remainder = 100 - percents.fold<int>(0, (sum, value) => sum + value);
  final order = List<int>.generate(exact.length, (index) => index)
    ..sort((left, right) {
      final byFraction = (exact[right] - percents[right]).compareTo(
        exact[left] - percents[left],
      );
      return byFraction != 0 ? byFraction : left.compareTo(right);
    });
  for (var index = 0; index < order.length && remainder > 0; index++) {
    percents[order[index]]++;
    remainder--;
  }

  return <AgentInterpretation>[
    for (var index = 0; index < clamped.length; index++)
      AgentInterpretation(
        id: clamped[index].id,
        label: clamped[index].label,
        meaning: clamped[index].meaning,
        confidence: percents[index] / 100,
        citationIds: clamped[index].citationIds,
      ),
  ];
}
