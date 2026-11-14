import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_analysis.dart';
import 'package:lexicandy/services/agent/analysis_merge.dart';

const _segmentA = AgentSegment(
  id: 's1',
  quoteId: 'q1',
  literal: '原文',
  interpretation: 'A义',
  epistemic: AgentEpistemic.dictionaryFact,
  confidence: 0.5,
  wordNotes: <AgentWordNote>[
    AgentWordNote(
      tokenId: 't1',
      surface: '何卒',
      reading: 'なにとぞ',
      sense: 'A义',
      citationIds: <String>['source-1'],
    ),
  ],
  grammarNotes: <AgentGrammarNote>[
    AgentGrammarNote(
      patternId: 'p1',
      explanation: 'A语法',
      citationIds: <String>['source-1'],
    ),
  ],
);

const _segmentB = AgentSegment(
  id: 's1',
  quoteId: 'q1',
  literal: '原文',
  interpretation: 'B义',
  epistemic: AgentEpistemic.dictionaryFact,
  confidence: 0.7,
  wordNotes: <AgentWordNote>[
    AgentWordNote(
      tokenId: 't1',
      surface: '何卒',
      reading: 'なにとぞ',
      sense: 'B义',
      citationIds: <String>['source-2'],
    ),
  ],
  grammarNotes: <AgentGrammarNote>[
    AgentGrammarNote(
      patternId: 'p1',
      explanation: 'B语法',
      citationIds: <String>['source-2'],
    ),
  ],
);

void main() {
  test('merges translations and segments in dictionary order', () {
    final merged = mergeDictionaryAnalyses(<AgentAnalysis>[
      const AgentAnalysis(
        sourceId: 'src-1',
        translation: <AgentTranslation>[
          AgentTranslation(quoteId: 'q1', text: 'A译文'),
        ],
        segments: <AgentSegment>[_segmentA],
        interpretations: <AgentInterpretation>[
          AgentInterpretation(
            id: 'i1',
            label: 'A',
            meaning: '含义A',
            confidence: 0.5,
            citationIds: <String>['source-1'],
          ),
        ],
        unresolved: <AgentUnresolved>[
          AgentUnresolved(quoteId: 'q1', reason: 'A未解决'),
        ],
        citationsUsed: <String>['source-1'],
        modelSupplements: <AgentModelSupplement>[
          AgentModelSupplement(text: '补充A'),
        ],
      ),
      const AgentAnalysis(
        sourceId: 'src-1',
        translation: <AgentTranslation>[
          AgentTranslation(quoteId: 'q1', text: 'B译文'),
        ],
        segments: <AgentSegment>[_segmentB],
        interpretations: <AgentInterpretation>[
          AgentInterpretation(
            id: 'i1',
            label: 'A',
            meaning: '含义B',
            confidence: 0.7,
            citationIds: <String>['source-2'],
          ),
        ],
        unresolved: <AgentUnresolved>[
          AgentUnresolved(quoteId: 'q1', reason: 'B未解决'),
        ],
        citationsUsed: <String>['source-2'],
        modelSupplements: <AgentModelSupplement>[
          AgentModelSupplement(text: '补充A'),
        ],
        truncated: true,
      ),
    ]);

    expect(merged.translation.single.text, 'A译文');
    expect(merged.segments, hasLength(1));
    expect(merged.segments.single.id, 's1');
    expect(merged.segments.single.interpretation, 'A义');
    expect(merged.segments.single.wordNotes, hasLength(2));
    expect(merged.segments.single.grammarNotes, hasLength(2));
    expect(merged.interpretations, hasLength(2));
    expect(merged.interpretations.map((item) => item.label), <String>[
      'A',
      'B',
    ]);
    expect(merged.interpretations.map((item) => item.id), <String>['i1', 'i2']);
    expect(merged.unresolved, hasLength(2));
    expect(merged.modelSupplements, hasLength(1));
    expect(merged.citationsUsed, containsAll(<String>['source-1', 'source-2']));
    expect(merged.truncated, isTrue);
  });

  test('an empty merge keeps the no-analysis reason', () {
    final merged = mergeDictionaryAnalyses(const <AgentAnalysis>[
      AgentAnalysis(sourceId: 'src-1', noAnalysisReason: '无可用分析'),
    ]);

    expect(merged.translation, isEmpty);
    expect(merged.segments, isEmpty);
    expect(merged.noAnalysisReason, '无可用分析');
  });

  test('re-indexes option labels and ids', () {
    final merged = mergeDictionaryAnalyses(const <AgentAnalysis>[
      AgentAnalysis(
        sourceId: 'src-1',
        interpretations: <AgentInterpretation>[
          AgentInterpretation(
            id: 'i1',
            label: '情况A',
            meaning: '含义A',
            confidence: 0.5,
          ),
          AgentInterpretation(
            id: 'i2',
            label: '情况B',
            meaning: '含义B',
            confidence: 0.5,
          ),
        ],
      ),
    ]);

    expect(merged.interpretations.map((item) => item.id), <String>['i1', 'i2']);
    expect(merged.interpretations.map((item) => item.label), <String>[
      'A',
      'B',
    ]);
  });
}
