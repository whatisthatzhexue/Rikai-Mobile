import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_quote.dart';

class AgentValidationResult {
  const AgentValidationResult({
    required this.valid,
    required this.errors,
    required this.citationsUsed,
  });

  final bool valid;
  final List<String> errors;
  final List<String> citationsUsed;
}

/// Enforces schema-level, citation, quote and strict-mode rules.
class AgentValidator {
  const AgentValidator();

  AgentValidationResult validate({
    required AgentAnalysis analysis,
    required AgentEvidenceBundle evidence,
    required List<AgentQuoteRef> quotes,
    required AgentMode mode,
    String? expectedSourceId,
  }) {
    final errors = <String>[];
    final citationMap = <String, AgentCitation>{
      for (final citation in evidence.citations) citation.id: citation,
    };
    final tokenMap = <String, AgentTokenEvidence>{};
    for (final source in evidence.sources) {
      for (final token in source.tokens) {
        tokenMap[token.id] = token;
      }
    }
    final patternMap = <String, AgentGrammarPatternEvidence>{
      for (final pattern in evidence.patterns) pattern.id: pattern,
    };
    final quoteMap = <String, AgentQuoteRef>{
      for (final quote in quotes) quote.id: quote,
    };
    final unresolvedQuotes = analysis.unresolved
        .map((item) => item.quoteId)
        .toSet();
    final used = <String>{};
    if (analysis.translation.isEmpty) {
      errors.add('模型没有返回译文');
    }
    if (analysis.segments.isEmpty) {
      errors.add('模型没有返回逐句结构');
    }
    if (expectedSourceId != null &&
        expectedSourceId.isNotEmpty &&
        analysis.sourceId != expectedSourceId) {
      errors.add('模型返回的 source_id 与本次输入不一致');
    }

    void validateCitations(
      List<String> ids,
      String where, {
      required bool requiredInStrict,
    }) {
      if (mode == AgentMode.strict && requiredInStrict && ids.isEmpty) {
        errors.add('$where 在严格模式下缺少词典依据');
      }
      for (final id in ids) {
        if (!citationMap.containsKey(id)) {
          errors.add('$where 引用了不存在的来源 $id');
        } else {
          used.add(id);
        }
      }
    }

    for (final translation in analysis.translation) {
      final quote = quoteMap[translation.quoteId];
      if (quote == null) {
        errors.add('译文引用了不存在的原文 ${translation.quoteId}');
      }
      if (translation.label != AgentTranslation.expectedLabel) {
        errors.add('译文必须标记为“${AgentTranslation.expectedLabel}”');
      }
      validateCitations(
        translation.citationIds,
        '译文 ${translation.quoteId}',
        requiredInStrict: false,
      );
    }

    for (final segment in analysis.segments) {
      final quote = quoteMap[segment.quoteId];
      if (quote == null) {
        errors.add('段落引用了不存在的原文 ${segment.quoteId}');
      } else if (segment.literal.isNotEmpty && segment.literal != quote.text) {
        errors.add('段落 ${segment.id} 改写了原文引用');
      }
      final claimCitations = <String>[];
      for (final note in segment.wordNotes) {
        if (!tokenMap.containsKey(note.tokenId)) {
          errors.add('词注引用了不存在的 token ${note.tokenId}');
        }
        validateCitations(
          note.citationIds,
          '词注 ${note.surface}',
          requiredInStrict: mode == AgentMode.strict,
        );
        claimCitations.addAll(note.citationIds);
        if (note.reading.isNotEmpty) {
          final token = tokenMap[note.tokenId];
          final tokenReading = token?.reading ?? '';
          if (tokenReading.isNotEmpty && tokenReading != note.reading) {
            errors.add('词注 ${note.surface} 的读音与 UniDic 不一致');
          } else if (tokenReading.isEmpty &&
              !note.citationIds.any(
                (id) => citationMap[id]?.snippet.contains(note.reading) == true,
              )) {
            errors.add('词注 ${note.surface} 的读音没有依据');
          }
        }
      }
      for (final note in segment.grammarNotes) {
        if (!patternMap.containsKey(note.patternId)) {
          errors.add('语法注引用了不存在的模式 ${note.patternId}');
        }
        validateCitations(
          note.citationIds,
          '语法注 ${note.patternId}',
          requiredInStrict:
              mode == AgentMode.strict &&
              segment.epistemic == AgentEpistemic.dictionaryFact,
        );
        claimCitations.addAll(note.citationIds);
        if (mode == AgentMode.strict &&
            segment.epistemic == AgentEpistemic.structuralAnalysis &&
            note.citationIds.isEmpty &&
            !patternMap.containsKey(note.patternId)) {
          errors.add('语法注 ${note.patternId} 缺少 UniDic 或词典依据');
        }
      }

      switch (segment.epistemic) {
        case AgentEpistemic.dictionaryFact:
          if (mode == AgentMode.strict &&
              claimCitations.isEmpty &&
              errors.isEmpty) {
            errors.add('段落 ${segment.id} 的词典事实没有 citation');
          }
        case AgentEpistemic.structuralAnalysis:
          if (evidence.structureUnavailable) {
            errors.add('UniDic 结构分析不可用，不能声明结构分析');
          } else if (segment.wordNotes.isEmpty &&
              segment.grammarNotes.isEmpty) {
            errors.add('段落 ${segment.id} 标为结构分析但没有任何 token/语法依据');
          }
        case AgentEpistemic.contextInference:
          if (mode == AgentMode.strict &&
              claimCitations.isEmpty &&
              !unresolvedQuotes.contains(segment.quoteId)) {
            errors.add('段落 ${segment.id} 的语境推断没有依据');
          }
        case AgentEpistemic.translation:
          break;
      }
    }

    for (final interpretation in analysis.interpretations) {
      if (interpretation.confidence < 0 || interpretation.confidence > 1) {
        errors.add('解释 ${interpretation.label} 的 confidence 超出 0–1');
      }
      validateCitations(
        interpretation.citationIds,
        '解释 ${interpretation.label}',
        requiredInStrict: mode == AgentMode.strict,
      );
    }
    for (final unresolved in analysis.unresolved) {
      if (!quoteMap.containsKey(unresolved.quoteId)) {
        errors.add('未解决项引用了不存在的原文 ${unresolved.quoteId}');
      }
      if (unresolved.reason.trim().isEmpty) {
        errors.add('未解决项缺少原因');
      }
    }
    for (final id in analysis.citationsUsed) {
      if (!citationMap.containsKey(id)) {
        errors.add('模型自报了不存在的来源 $id');
      }
    }
    if (mode == AgentMode.strict && analysis.modelSupplements.isNotEmpty) {
      errors.add('严格模式不能返回模型补充');
    }

    return AgentValidationResult(
      valid: errors.isEmpty,
      errors: List<String>.unmodifiable(errors),
      citationsUsed: List<String>.unmodifiable(used),
    );
  }
}
