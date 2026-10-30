import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/services/agent/analysis_normalizer.dart';

void main() {
  test('restores literal from the quote and drops unknown pattern ids', () {
    const quote = AgentQuoteRef(
      id: 'q1',
      sourceId: 'src-1',
      start: 0,
      end: 2,
      text: '何卒',
      origin: AgentQuoteOrigin.userText,
    );
    const evidence = AgentEvidenceBundle(
      sources: <AgentSourceEvidence>[],
      patterns: <AgentGrammarPatternEvidence>[
        AgentGrammarPatternEvidence(
          id: 'p1',
          surface: '何卒',
          tokenIds: <String>['t1'],
          start: 0,
          end: 2,
        ),
      ],
    );
    final normalized = normalizeAnalysis(
      analysis: const AgentAnalysis(
        sourceId: 'src-1',
        translation: <AgentTranslation>[
          AgentTranslation(quoteId: 'q1', text: '请多关照。'),
        ],
        segments: <AgentSegment>[
          AgentSegment(
            id: 'seg-1',
            quoteId: 'q1',
            literal: '被改写的原文',
            interpretation: '正式请求',
            epistemic: AgentEpistemic.dictionaryFact,
            grammarNotes: <AgentGrammarNote>[
              AgentGrammarNote(patternId: 't1+t2', explanation: '模型自造模式'),
            ],
          ),
        ],
      ),
      quotes: const <AgentQuoteRef>[quote],
      evidence: evidence,
    );

    expect(normalized.segments.single.literal, '何卒');
    expect(normalized.segments.single.grammarNotes, isEmpty);
    expect(normalized.translation.single.text, '请多关照。');
  });
}
