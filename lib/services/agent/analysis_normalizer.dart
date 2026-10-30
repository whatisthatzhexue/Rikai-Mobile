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
    interpretations: analysis.interpretations,
    unresolved: analysis.unresolved,
    citationsUsed: analysis.citationsUsed,
    modelSupplements: analysis.modelSupplements,
  );
}
