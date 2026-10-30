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
          reading: 'なにとぞ',
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
            tokenId: 't1',
            surface: '何卒',
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
}
