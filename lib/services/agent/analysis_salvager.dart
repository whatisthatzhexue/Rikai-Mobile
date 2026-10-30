import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_quote.dart';

class AnalysisSalvageResult {
  const AnalysisSalvageResult({required this.analysis, required this.notes});

  final AgentAnalysis analysis;
  final List<String> notes;

  bool get hasContent =>
      analysis.translation.isNotEmpty || analysis.segments.isNotEmpty;
}

/// Keeps every claim that can be safely displayed after validation failed.
///
/// This is deliberately conservative: invalid citations are removed, notes
/// that point at unknown tokens/patterns are dropped, and in strict mode
/// unsupported dictionary facts/context inference become `unresolved` instead
/// of being shown as verified claims. The salvaged analysis still carries the
/// original quote text; it never rewrites the source.
AnalysisSalvageResult salvageAnalysis({
  required AgentAnalysis analysis,
  required AgentEvidenceBundle evidence,
  required List<AgentQuoteRef> quotes,
  required AgentMode mode,
  String? expectedSourceId,
}) {
  final quoteIds = quotes.map((quote) => quote.id).toSet();
  final citationIds = evidence.citations.map((item) => item.id).toSet();
  final tokenReadings = <String, String>{
    for (final source in evidence.sources)
      for (final token in source.tokens) token.id: token.reading,
  };
  final patternIds = evidence.patterns.map((item) => item.id).toSet();
  final notes = <String>[];
  final unresolved = <AgentUnresolved>[];
  final unresolvedQuotes = <String>{};

  void addUnresolved(String quoteId, String reason) {
    if (!quoteIds.contains(quoteId) || !unresolvedQuotes.add(quoteId)) return;
    unresolved.add(AgentUnresolved(quoteId: quoteId, reason: reason));
  }

  List<String> keepCitations(List<String> ids, {required bool required}) {
    final kept = <String>[
      for (final id in ids)
        if (citationIds.contains(id)) id,
    ];
    if (kept.length != ids.length) notes.add('已移除无效 citation');
    if (required && kept.isEmpty) return const <String>[];
    return kept;
  }

  final translations = <AgentTranslation>[];
  for (final item in analysis.translation) {
    if (!quoteIds.contains(item.quoteId) || item.text.trim().isEmpty) {
      notes.add('已移除无法对应原文的译文');
      continue;
    }
    translations.add(
      AgentTranslation(
        quoteId: item.quoteId,
        text: item.text,
        citationIds: keepCitations(item.citationIds, required: false),
      ),
    );
  }

  final segments = <AgentSegment>[];
  for (final segment in analysis.segments) {
    if (!quoteIds.contains(segment.quoteId)) {
      notes.add('已移除无法对应原文的段落');
      continue;
    }
    if (evidence.structureUnavailable &&
        segment.epistemic == AgentEpistemic.structuralAnalysis) {
      notes.add('已移除无 UniDic 依据的结构分析');
      continue;
    }
    final wordNotes = <AgentWordNote>[];
    for (final note in segment.wordNotes) {
      if (!tokenReadings.containsKey(note.tokenId)) {
        notes.add('已移除未知 token 的词注');
        continue;
      }
      final kept = keepCitations(note.citationIds, required: false);
      if (mode == AgentMode.strict && kept.isEmpty) {
        notes.add('已移除无词典依据的词注');
        continue;
      }
      final tokenReading = tokenReadings[note.tokenId] ?? '';
      final reading =
          note.reading.isNotEmpty &&
              tokenReading.isNotEmpty &&
              note.reading != tokenReading
          ? ''
          : note.reading;
      if (reading != note.reading) notes.add('已清除与 UniDic 不一致的读音');
      wordNotes.add(
        AgentWordNote(
          tokenId: note.tokenId,
          surface: note.surface,
          reading: reading,
          sense: note.sense,
          citationIds: kept,
        ),
      );
    }
    final grammarNotes = <AgentGrammarNote>[];
    for (final note in segment.grammarNotes) {
      if (!patternIds.contains(note.patternId)) {
        notes.add('已移除未知语法模式');
        continue;
      }
      final kept = keepCitations(note.citationIds, required: false);
      grammarNotes.add(
        AgentGrammarNote(
          patternId: note.patternId,
          explanation: note.explanation,
          citationIds: kept,
        ),
      );
    }
    final claimCitations = <String>{
      for (final note in wordNotes) ...note.citationIds,
      for (final note in grammarNotes) ...note.citationIds,
    };
    var epistemic = segment.epistemic;
    if (epistemic == AgentEpistemic.structuralAnalysis &&
        wordNotes.isEmpty &&
        grammarNotes.isEmpty) {
      notes.add('已移除无 token/语法依据的结构分析');
      continue;
    }
    if (mode == AgentMode.strict &&
        epistemic == AgentEpistemic.dictionaryFact &&
        claimCitations.isEmpty) {
      addUnresolved(segment.quoteId, '词典中未找到依据');
      continue;
    }
    if (mode == AgentMode.strict &&
        epistemic == AgentEpistemic.contextInference &&
        claimCitations.isEmpty) {
      addUnresolved(segment.quoteId, '没有足够依据，无法确定语境含义');
      continue;
    }
    segments.add(
      AgentSegment(
        id: segment.id,
        quoteId: segment.quoteId,
        literal: segment.literal,
        interpretation: segment.interpretation,
        epistemic: epistemic,
        confidence: segment.confidence.clamp(0, 1).toDouble(),
        wordNotes: wordNotes,
        grammarNotes: grammarNotes,
      ),
    );
  }

  final interpretations = <AgentInterpretation>[];
  for (final item in analysis.interpretations) {
    final kept = keepCitations(item.citationIds, required: false);
    if (mode == AgentMode.strict && kept.isEmpty) {
      notes.add('已移除无依据的多种解释');
      continue;
    }
    interpretations.add(
      AgentInterpretation(
        id: item.id,
        label: item.label,
        meaning: item.meaning,
        confidence: item.confidence.clamp(0, 1).toDouble(),
        citationIds: kept,
      ),
    );
  }

  for (final item in analysis.unresolved) {
    addUnresolved(item.quoteId, item.reason);
  }

  final supplements = mode == AgentMode.loose
      ? analysis.modelSupplements
      : const <AgentModelSupplement>[];
  final used = <String>{
    for (final item in translations) ...item.citationIds,
    for (final segment in segments) ...{
      for (final note in segment.wordNotes) ...note.citationIds,
      for (final note in segment.grammarNotes) ...note.citationIds,
    },
    for (final item in interpretations) ...item.citationIds,
  };
  final sourceId = expectedSourceId?.isNotEmpty == true
      ? expectedSourceId!
      : analysis.sourceId;
  final result = AgentAnalysis(
    sourceId: sourceId,
    translation: translations,
    segments: segments,
    interpretations: interpretations,
    unresolved: unresolved,
    citationsUsed: used.toList(growable: false),
    modelSupplements: supplements,
  );
  return AnalysisSalvageResult(
    analysis: result,
    notes: notes.toSet().toList(growable: false),
  );
}
