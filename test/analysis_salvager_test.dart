import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/services/agent/analysis_salvager.dart';

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
      snippet: 'なにとぞ。',
      toolCallId: 'call-1',
    ),
    AgentCitation(
      id: 'source-2',
      kind: 'mdict',
      dictionaryId: 'dict_b',
      dictionaryTitle: 'B',
      dictionaryOrder: 1,
      entryKey: '東京',
      headword: '東京',
      snippet: 'とうきょう。',
      toolCallId: 'call-2',
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

void main() {
  test(
    'salvage keeps free grammar notes and word fallbacks accepted by validator',
    () {
      final analysis = AgentAnalysis(
        sourceId: 'src-1',
        translation: const <AgentTranslation>[
          AgentTranslation(quoteId: 'q1', text: '请多关照。'),
        ],
        segments: const <AgentSegment>[
          AgentSegment(
            id: 'seg-1',
            quoteId: 'q1',
            literal: '何卒',
            interpretation: '正式请求',
            epistemic: AgentEpistemic.structuralAnalysis,
            wordNotes: <AgentWordNote>[
              // No token id, but the surface is unique inside q1.
              AgentWordNote(
                tokenId: '',
                surface: '何卒',
                reading: 'ナニトゾ',
                sense: '请务必',
                citationIds: <String>['source-1'],
              ),
            ],
            grammarNotes: <AgentGrammarNote>[
              // Free grammar note: the whitelist did not match.
              AgentGrammarNote(
                patternId: '',
                explanation: '礼貌请求的表达',
                citationIds: <String>['source-1'],
              ),
            ],
          ),
        ],
      );

      final result = salvageAnalysis(
        analysis: analysis,
        evidence: _evidence,
        quotes: _quotes,
        mode: AgentMode.strict,
      );

      final segment = result.analysis.segments.single;
      expect(segment.wordNotes, hasLength(1));
      expect(segment.wordNotes.single.tokenId, 't1');
      // UniDic reading is hiragana in the fixture; katakana is equivalent.
      expect(segment.wordNotes.single.reading, 'ナニトゾ');
      expect(segment.grammarNotes, hasLength(1));
      expect(segment.grammarNotes.single.patternId, isEmpty);
      expect(segment.grammarNotes.single.citationIds, <String>['source-1']);
    },
  );

  test('salvage drops citations that are not attributed to the token', () {
    final analysis = AgentAnalysis(
      sourceId: 'src-1',
      translation: const <AgentTranslation>[
        AgentTranslation(quoteId: 'q1', text: '请多关照。'),
      ],
      segments: const <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          literal: '何卒',
          interpretation: '正式请求',
          epistemic: AgentEpistemic.dictionaryFact,
          wordNotes: <AgentWordNote>[
            AgentWordNote(
              tokenId: 't1',
              surface: '何卒',
              sense: '请务必',
              citationIds: <String>['source-1'],
            ),
            AgentWordNote(
              tokenId: 't1',
              surface: '何卒',
              sense: '错误引用',
              citationIds: <String>['source-2'],
            ),
          ],
        ),
      ],
    );

    final result = salvageAnalysis(
      analysis: analysis,
      evidence: _evidence,
      quotes: _quotes,
      mode: AgentMode.strict,
    );

    expect(result.hasContent, isTrue);
    expect(result.analysis.segments, hasLength(1));
    final notes = result.analysis.segments.single.wordNotes;
    expect(notes, hasLength(1));
    expect(notes.single.citationIds, <String>['source-1']);
    expect(result.notes.any((note) => note.contains('未归属')), isTrue);
  });
}
