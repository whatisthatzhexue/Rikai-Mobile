import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_evidence.dart';
import 'package:lexicandy/services/agent/evidence_partition.dart';

AgentCitation _citation(String id, String dictionaryId) {
  return AgentCitation(
    id: id,
    kind: 'mdict',
    dictionaryId: dictionaryId,
    dictionaryTitle: dictionaryId,
    dictionaryOrder: dictionaryId == 'dict-a' ? 0 : 1,
    entryKey: '何卒',
    headword: '何卒',
    snippet: 'なにとぞ。',
    toolCallId: 'call-1',
  );
}

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
          start: 0,
          end: 2,
          citationIds: <String>['source-1'],
        ),
        AgentTokenEvidence(
          id: 't2',
          surface: '何卒',
          start: 0,
          end: 2,
          citationIds: <String>['source-2'],
        ),
      ],
    ),
  ],
  patterns: <AgentGrammarPatternEvidence>[
    AgentGrammarPatternEvidence(
      id: 'p1',
      surface: '何卒',
      tokenIds: <String>['t1'],
      start: 0,
      end: 2,
      citationIds: <String>['source-1', 'source-2'],
    ),
  ],
  citations: <AgentCitation>[],
  dictionaryIssues: <AgentEvidenceDictionaryIssue>[
    AgentEvidenceDictionaryIssue(
      dictionaryId: 'dict-a',
      dictionaryTitle: 'A',
      code: 'LOOKUP_FAILED',
      message: 'a',
    ),
    AgentEvidenceDictionaryIssue(
      dictionaryId: 'dict-b',
      dictionaryTitle: 'B',
      code: 'LOOKUP_FAILED',
      message: 'b',
    ),
  ],
  budget: AgentEvidenceBudget(
    uniqueTargets: 2,
    targetsWithCitations: 2,
    citations: 2,
    maxTargets: 120,
    maxCitations: 60,
  ),
);

void main() {
  test('partitions citations, token links and issues by dictionary', () {
    final partitioned = evidenceForDictionary(
      AgentEvidenceBundle(
        sources: _evidence.sources,
        patterns: _evidence.patterns,
        citations: <AgentCitation>[
          _citation('source-1', 'dict-a'),
          _citation('source-2', 'dict-b'),
        ],
        dictionaryIssues: _evidence.dictionaryIssues,
        budget: _evidence.budget,
      ),
      'dict-a',
    );

    expect(partitioned.citations.map((item) => item.id), <String>['source-1']);
    expect(partitioned.sources.single.tokens.first.citationIds, <String>[
      'source-1',
    ]);
    expect(partitioned.sources.single.tokens.last.citationIds, isEmpty);
    expect(partitioned.patterns.single.citationIds, <String>['source-1']);
    expect(partitioned.dictionaryIssues.single.dictionaryId, 'dict-a');
    expect(partitioned.sources.single.text, '何卒');
    expect(partitioned.budget.citations, 1);
  });

  test('an unknown dictionary yields no citations but keeps source text', () {
    final partitioned = evidenceForDictionary(
      AgentEvidenceBundle(
        sources: _evidence.sources,
        patterns: _evidence.patterns,
        citations: <AgentCitation>[
          _citation('source-1', 'dict-a'),
          _citation('source-2', 'dict-b'),
        ],
        dictionaryIssues: _evidence.dictionaryIssues,
        budget: _evidence.budget,
      ),
      'dict-missing',
    );

    expect(partitioned.citations, isEmpty);
    expect(partitioned.sources.single.text, '何卒');
    expect(partitioned.sources.single.tokens.first.citationIds, isEmpty);
    expect(partitioned.patterns.single.citationIds, isEmpty);
    expect(partitioned.dictionaryIssues, isEmpty);
    expect(partitioned.budget.citations, 0);
  });
}
