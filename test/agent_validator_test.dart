import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/services/agent/agent_validator.dart';

const _evidence = AgentEvidenceBundle(
  sources: <AgentSourceEvidence>[
    AgentSourceEvidence(
      id: 'src-1',
      kind: 'user_text',
      text: '何卒',
      tokens: <AgentTokenEvidence>[
        AgentTokenEvidence(
          id: 't1',
          surface: '何卒',
          // Real UniDic readings are katakana; the model often writes
          // hiragana. Validation must compare normalized kana.
          reading: 'ナニトゾ',
          start: 0,
          end: 2,
          content: true,
          citationIds: <String>['source-1'],
        ),
      ],
    ),
  ],
  citations: <AgentCitation>[
    AgentCitation(
      id: 'source-1',
      kind: 'mdict',
      dictionaryId: 'dict_a',
      dictionaryTitle: 'A',
      dictionaryOrder: 0,
      entryKey: '何卒',
      headword: '何卒',
      snippet: 'なにとぞ。どうか。',
      toolCallId: 'call-1',
    ),
  ],
);

const _quotes = <AgentQuoteRef>[
  AgentQuoteRef(
    id: 'q1',
    sourceId: 'src-1',
    start: 0,
    end: 2,
    text: '何卒',
    origin: AgentQuoteOrigin.userText,
  ),
];

AgentAnalysis _analysis({
  String literal = '何卒',
  String reading = '',
  String tokenId = 't1',
  List<String> citationIds = const <String>['source-1'],
  AgentEpistemic epistemic = AgentEpistemic.dictionaryFact,
  List<AgentModelSupplement> supplements = const <AgentModelSupplement>[],
  List<AgentUnresolved> unresolved = const <AgentUnresolved>[],
}) {
  return AgentAnalysis(
    sourceId: 'src-1',
    translation: const <AgentTranslation>[
      AgentTranslation(quoteId: 'q1', text: '请多关照。'),
    ],
    segments: <AgentSegment>[
      AgentSegment(
        id: 'seg-1',
        quoteId: 'q1',
        literal: literal,
        interpretation: '正式请求',
        epistemic: epistemic,
        wordNotes: <AgentWordNote>[
          AgentWordNote(
            tokenId: tokenId,
            surface: '何卒',
            reading: reading,
            sense: '请务必',
            citationIds: citationIds,
          ),
        ],
      ),
    ],
    unresolved: unresolved,
    modelSupplements: supplements,
  );
}

const _citationB = AgentCitation(
  id: 'source-2',
  kind: 'mdict',
  dictionaryId: 'dict_b',
  dictionaryTitle: 'B',
  dictionaryOrder: 1,
  entryKey: '東京',
  headword: '東京',
  snippet: 'とうきょう。',
  toolCallId: 'call-2',
);

void main() {
  const validator = AgentValidator();

  test('strict mode accepts a cited dictionary fact with an exact quote', () {
    final result = validator.validate(
      analysis: _analysis(),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(result.valid, isTrue);
    expect(result.citationsUsed, ['source-1']);
  });

  test('missing citations and rewritten quotes are rejected', () {
    final missing = validator.validate(
      analysis: _analysis(citationIds: const <String>[]),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(missing.valid, isFalse);
    expect(missing.errors.any((error) => error.contains('缺少词典依据')), isTrue);
    // The segment-level fact error must not be suppressed by an earlier error.
    expect(
      missing.errors.any((error) => error.contains('词典事实没有 citation')),
      isTrue,
    );

    final rewritten = validator.validate(
      analysis: _analysis(literal: '改写'),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(rewritten.valid, isFalse);
    expect(rewritten.errors.any((error) => error.contains('改写了原文')), isTrue);
  });

  test('unknown citations are rejected', () {
    final result = validator.validate(
      analysis: _analysis(citationIds: const <String>['source-99']),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(result.valid, isFalse);
    expect(result.errors.any((error) => error.contains('source-99')), isTrue);
  });

  test('strict mode hides model supplements; loose mode allows them', () {
    const supplement = AgentModelSupplement(text: '也可用于邮件');
    final strict = validator.validate(
      analysis: _analysis(
        supplements: const <AgentModelSupplement>[supplement],
      ),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(strict.valid, isFalse);
    expect(strict.errors.any((error) => error.contains('模型补充')), isTrue);

    final loose = validator.validate(
      analysis: _analysis(
        supplements: const <AgentModelSupplement>[supplement],
      ),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.loose,
    );
    expect(loose.valid, isTrue);
  });

  test('uncited context inference must be unresolved in strict mode', () {
    final inference = _analysis(
      citationIds: const <String>[],
      epistemic: AgentEpistemic.contextInference,
    );
    final invalid = validator.validate(
      analysis: inference,
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(invalid.valid, isFalse);

    final resolved = validator.validate(
      analysis: AgentAnalysis(
        sourceId: inference.sourceId,
        translation: inference.translation,
        segments: const <AgentSegment>[
          AgentSegment(
            id: 'seg-1',
            quoteId: 'q1',
            interpretation: '无法确定',
            epistemic: AgentEpistemic.contextInference,
          ),
        ],
        unresolved: const <AgentUnresolved>[
          AgentUnresolved(quoteId: 'q1', reason: '词典中未找到依据'),
        ],
      ),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(resolved.valid, isTrue);
  });

  test('a standalone NO_ANALYSIS result is valid', () {
    final result = validator.validate(
      analysis: const AgentAnalysis(
        sourceId: 'src-1',
        noAnalysisReason: 'OCR 文本无法辨认',
      ),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(result.valid, isTrue);
    expect(result.citationsUsed, isEmpty);
  });

  test('NO_ANALYSIS cannot be combined with translation or segments', () {
    final result = validator.validate(
      analysis: AgentAnalysis(
        sourceId: 'src-1',
        noAnalysisReason: '无法辨认',
        translation: _analysis().translation,
      ),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(result.valid, isFalse);
    expect(result.errors.any((error) => error.contains('NO_ANALYSIS')), isTrue);
  });

  test('strict mode requires citations on OPTION blocks', () {
    final analysis = AgentAnalysis(
      sourceId: 'src-1',
      translation: _analysis().translation,
      segments: _analysis().segments,
      interpretations: const <AgentInterpretation>[
        AgentInterpretation(
          id: 'i1',
          label: 'A',
          meaning: '另一种理解',
          confidence: 0.7,
        ),
      ],
    );
    final result = validator.validate(
      analysis: analysis,
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(result.valid, isFalse);
    expect(
      result.errors.any((error) => error.contains('解释 A 在严格模式下缺少词典依据')),
      isTrue,
    );
  });

  test('word note citations must belong to the token evidence', () {
    final evidence = AgentEvidenceBundle(
      sources: _evidence.sources,
      citations: <AgentCitation>[..._evidence.citations, _citationB],
    );
    final strict = validator.validate(
      analysis: _analysis(citationIds: const <String>['source-2']),
      evidence: evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(strict.valid, isFalse);
    expect(strict.errors.any((error) => error.contains('不属于该词条的检索结果')), isTrue);

    final loose = validator.validate(
      analysis: _analysis(citationIds: const <String>['source-2']),
      evidence: evidence,
      quotes: _quotes,
      mode: AgentMode.loose,
    );
    expect(loose.valid, isFalse);
    expect(loose.errors.any((error) => error.contains('不属于该词条的检索结果')), isTrue);
  });

  test('grammar note citations must belong to the pattern or its tokens', () {
    final pattern = AgentGrammarPatternEvidence(
      id: 'p1',
      surface: '何卒',
      tokenIds: const <String>['t1'],
      start: 0,
      end: 2,
      citationIds: const <String>['source-1'],
    );
    final evidence = AgentEvidenceBundle(
      sources: _evidence.sources,
      patterns: <AgentGrammarPatternEvidence>[pattern],
      citations: <AgentCitation>[..._evidence.citations, _citationB],
    );
    AgentAnalysis analysisWith(List<String> citationIds) => AgentAnalysis(
      sourceId: 'src-1',
      translation: _analysis().translation,
      segments: <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          literal: '何卒',
          interpretation: '正式请求',
          epistemic: AgentEpistemic.structuralAnalysis,
          grammarNotes: <AgentGrammarNote>[
            AgentGrammarNote(
              patternId: 'p1',
              explanation: '副词修饰',
              citationIds: citationIds,
            ),
          ],
        ),
      ],
    );

    final linked = validator.validate(
      analysis: analysisWith(const <String>['source-1']),
      evidence: evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(linked.valid, isTrue);

    final unrelated = validator.validate(
      analysis: analysisWith(const <String>['source-2']),
      evidence: evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(unrelated.valid, isFalse);
    expect(
      unrelated.errors.any((error) => error.contains('不属于该模式或组成词')),
      isTrue,
    );
  });

  test('word reading comparison ignores hiragana/katakana script', () {
    final hiragana = validator.validate(
      analysis: _analysis(reading: 'なにとぞ'),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(hiragana.valid, isTrue);

    final katakana = validator.validate(
      analysis: _analysis(reading: 'ナニトゾ'),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(katakana.valid, isTrue);

    final wrong = validator.validate(
      analysis: _analysis(reading: 'たかし'),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(wrong.valid, isFalse);
    expect(
      wrong.errors.any((error) => error.contains('读音与 UniDic 不一致')),
      isTrue,
    );
  });

  test('word note falls back to a unique surface inside the quote', () {
    for (final tokenId in <String>['', 't99']) {
      final result = validator.validate(
        analysis: _analysis(tokenId: tokenId, reading: 'なにとぞ'),
        evidence: _evidence,
        quotes: _quotes,
        mode: AgentMode.strict,
      );
      expect(result.valid, isTrue, reason: 'tokenId=$tokenId');
    }
  });

  test('free grammar notes do not require a supplied pattern id', () {
    AgentAnalysis analysisWith(String patternId, List<String> citationIds) {
      return AgentAnalysis(
        sourceId: 'src-1',
        translation: _analysis().translation,
        segments: <AgentSegment>[
          AgentSegment(
            id: 'seg-1',
            quoteId: 'q1',
            literal: '何卒',
            interpretation: '正式请求',
            epistemic: AgentEpistemic.structuralAnalysis,
            grammarNotes: <AgentGrammarNote>[
              AgentGrammarNote(
                patternId: patternId,
                explanation: '「何卒」是副词',
                citationIds: citationIds,
              ),
            ],
          ),
        ],
      );
    }

    final emptyId = validator.validate(
      analysis: analysisWith('', const <String>['source-1']),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(emptyId.valid, isTrue);

    final unknownId = validator.validate(
      analysis: analysisWith('p99', const <String>['source-1']),
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(unknownId.valid, isTrue);

    final evidenceWithOther = AgentEvidenceBundle(
      sources: _evidence.sources,
      citations: <AgentCitation>[..._evidence.citations, _citationB],
    );
    final unrelated = validator.validate(
      analysis: analysisWith('', const <String>['source-2']),
      evidence: evidenceWithOther,
      quotes: _quotes,
      mode: AgentMode.strict,
    );
    expect(unrelated.valid, isFalse);
    expect(unrelated.errors.any((error) => error.contains('原文范围内')), isTrue);
  });

  test('usable survives JSON while contract validity stays false', () {
    const validation = AgentValidationResult(
      valid: false,
      usable: true,
      errors: <String>['cleaned locally'],
      citationsUsed: <String>['source-1'],
    );
    final decoded = AgentValidationResult.fromJson(validation.toJson());

    expect(decoded.valid, isFalse);
    expect(decoded.usable, isTrue);
    expect(decoded.displayable, isTrue);
    expect(decoded.errors, <String>['cleaned locally']);
  });
}
