import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_json.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/utils/kana.dart';
import '../../core/utils/text_normalizer.dart';

class AgentValidationResult {
  const AgentValidationResult({
    required this.valid,
    required this.errors,
    required this.citationsUsed,
  });

  final bool valid;
  final List<String> errors;
  final List<String> citationsUsed;

  Map<String, Object?> toJson() => <String, Object?>{
    'valid': valid,
    'errors': errors,
    'citations_used': citationsUsed,
  };

  factory AgentValidationResult.fromJson(Map<String, Object?> json) {
    return AgentValidationResult(
      valid: agentBool(json['valid']),
      errors: agentStringList(json['errors']),
      citationsUsed: agentStringList(json['citations_used']),
    );
  }
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
    final noAnalysisReason = analysis.noAnalysisReason.trim();
    if (noAnalysisReason.isNotEmpty) {
      if (analysis.translation.isNotEmpty ||
          analysis.segments.isNotEmpty ||
          analysis.interpretations.isNotEmpty ||
          analysis.modelSupplements.isNotEmpty) {
        errors.add('NO_ANALYSIS 不能与其他分析结果共存');
      }
      return AgentValidationResult(
        valid: errors.isEmpty,
        errors: List<String>.unmodifiable(errors),
        citationsUsed: const <String>[],
      );
    }
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
    // Free grammar notes (no supplied pattern id) may only cite tokens that
    // overlap their quote. This keeps strict traceability without rejecting a
    // valid grammar explanation just because the whitelist did not match it.
    final quoteTokenIds = <String, Set<String>>{
      for (final quote in quotes)
        quote.id: <String>{
          for (final source in evidence.sources)
            if (source.id == quote.sourceId)
              for (final token in source.tokens)
                if (token.start < quote.end && token.end > quote.start)
                  token.id,
        },
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
        // Some models omit WORD id or use a display surface instead. Resolve a
        // unique surface/lemma within the current quote before rejecting the
        // note; this keeps traceability without failing an otherwise correct
        // analysis on a formatting omission.
        final token = _resolveWordToken(
          note,
          segment.quoteId,
          tokenMap,
          quoteTokenIds,
        );
        if (token == null) {
          errors.add('词注引用了不存在的 token ${note.tokenId}');
        }
        validateCitations(
          note.citationIds,
          '词注 ${note.surface}',
          requiredInStrict: mode == AgentMode.strict,
        );
        // A citation ID existing is not enough: it must be one of the entries
        // retrieved for this token. Otherwise a model can attach dictionary A's
        // entry to a word that only dictionary B covered.
        if (token != null &&
            note.citationIds.isNotEmpty &&
            note.citationIds.any((id) => !token.citationIds.contains(id))) {
          errors.add('词注 ${note.surface} 的 citation 不属于该词条的检索结果');
        }
        claimCitations.addAll(note.citationIds);
        if (note.reading.isNotEmpty) {
          final noteReading = _normalizeReading(note.reading);
          final tokenReading = token?.reading ?? '';
          if (noteReading.isNotEmpty &&
              tokenReading.isNotEmpty &&
              _normalizeReading(tokenReading) != noteReading) {
            errors.add('词注 ${note.surface} 的读音与 UniDic 不一致');
          } else if (noteReading.isNotEmpty &&
              tokenReading.isEmpty &&
              !note.citationIds.any((id) {
                final snippet = citationMap[id]?.snippet ?? '';
                return snippet.isNotEmpty &&
                    _normalizeReading(snippet).contains(noteReading);
              })) {
            errors.add('词注 ${note.surface} 的读音没有依据');
          }
        }
      }
      for (final note in segment.grammarNotes) {
        // A model may explain grammar that is not in the supplied pattern
        // whitelist. An empty/unknown pattern id is treated as a free grammar
        // note; its citations must still come from tokens overlapping the
        // current quote. This avoids invalidating an otherwise correct result
        // just because the whitelist had no matching pattern.
        final pattern = note.patternId.isEmpty
            ? null
            : patternMap[note.patternId];
        validateCitations(
          note.citationIds,
          '语法注 ${note.patternId.isEmpty ? note.explanation : note.patternId}',
          requiredInStrict:
              mode == AgentMode.strict &&
              segment.epistemic == AgentEpistemic.dictionaryFact,
        );
        if (note.citationIds.isNotEmpty) {
          final allowed = pattern != null
              ? <String>{
                  ...pattern.citationIds,
                  for (final tokenId in pattern.tokenIds)
                    ...?tokenMap[tokenId]?.citationIds,
                }
              : <String>{
                  for (final tokenId
                      in quoteTokenIds[segment.quoteId] ?? const <String>{})
                    ...?tokenMap[tokenId]?.citationIds,
                };
          if (note.citationIds.any((id) => !allowed.contains(id))) {
            errors.add(
              '语法注 ${note.patternId.isEmpty ? note.explanation : note.patternId} '
              '${pattern != null ? '的 citation 不属于该模式或组成词的检索结果' : '的 citation 不属于原文范围内的检索结果'}',
            );
          }
        }
        claimCitations.addAll(note.citationIds);
        if (mode == AgentMode.strict &&
            segment.epistemic == AgentEpistemic.structuralAnalysis &&
            note.citationIds.isEmpty &&
            pattern == null) {
          errors.add(
            '语法注 ${note.patternId.isEmpty ? note.explanation : note.patternId} '
            '缺少 UniDic 或词典依据',
          );
        }
      }

      switch (segment.epistemic) {
        case AgentEpistemic.dictionaryFact:
          if (mode == AgentMode.strict && claimCitations.isEmpty) {
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

AgentTokenEvidence? _resolveWordToken(
  AgentWordNote note,
  String quoteId,
  Map<String, AgentTokenEvidence> tokenMap,
  Map<String, Set<String>> quoteTokenIds,
) {
  final direct = tokenMap[note.tokenId];
  if (direct != null) return direct;
  final surface = note.surface.trim();
  if (surface.isEmpty) return null;
  final matches = <AgentTokenEvidence>[];
  for (final tokenId in quoteTokenIds[quoteId] ?? const <String>{}) {
    final token = tokenMap[tokenId];
    if (token != null && (token.surface == surface || token.lemma == surface)) {
      matches.add(token);
    }
  }
  return matches.length == 1 ? matches.single : null;
}

/// UniDic readings are commonly katakana while a model writes hiragana (or
/// vice versa). Compare normalized kana, not raw code units, so a correct
/// reading is never reported as "inconsistent with UniDic".
String _normalizeReading(String value) {
  return katakanaToHiragana(
    normalizeLookupText(value),
  ).replaceAll(RegExp(r'[\s・]'), '');
}
