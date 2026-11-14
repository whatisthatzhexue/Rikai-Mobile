import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_analysis.dart';
import 'package:lexicandy/core/models/agent/agent_evidence.dart';
import 'package:lexicandy/core/models/agent/agent_quote.dart';
import 'package:lexicandy/services/agent/analysis_normalizer.dart';

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
        interpretations: <AgentInterpretation>[
          AgentInterpretation(
            id: 'i1',
            label: 'A',
            meaning: '起点',
            confidence: 0.7,
            citationIds: <String>['source-1'],
          ),
          AgentInterpretation(
            id: 'i2',
            label: 'B',
            meaning: '原因',
            confidence: 0.7,
            citationIds: <String>['source-2'],
          ),
        ],
      ),
      quotes: const <AgentQuoteRef>[quote],
      evidence: evidence,
    );

    expect(normalized.segments.single.literal, '何卒');
    expect(normalized.segments.single.grammarNotes, isEmpty);
    expect(normalized.translation.single.text, '请多关照。');
    // The parser gives both cited OPTION blocks 0.7. The pipeline must show a
    // distribution (50/50), not two independent 70% values summing to 140%.
    expect(normalized.interpretations.map((item) => item.confidence), <double>[
      0.5,
      0.5,
    ]);
    expect(
      normalized.interpretations.fold<double>(
        0,
        (sum, item) => sum + item.confidence,
      ),
      closeTo(1.0, 1e-9),
    );

    final thirds = normalizeInterpretationConfidences(const <
      AgentInterpretation
    >[
      AgentInterpretation(id: 'i1', label: 'A', meaning: 'a', confidence: 0.7),
      AgentInterpretation(id: 'i2', label: 'B', meaning: 'b', confidence: 0.7),
      AgentInterpretation(id: 'i3', label: 'C', meaning: 'c', confidence: 0.7),
    ]);
    expect(thirds.map((item) => (item.confidence * 100).round()), <int>[
      34,
      33,
      33,
    ]);
    expect(
      thirds.fold<double>(0, (sum, item) => sum + item.confidence),
      closeTo(1.0, 1e-9),
    );
  });
}
