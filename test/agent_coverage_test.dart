import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_coverage.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/services/agent/agent_coverage_parser.dart';
import 'package:rikai_mobile/services/agent/coverage_support.dart';

const _input = AgentInputEnvelope(
  sessionId: 's1',
  mode: AgentMode.strict,
  sources: <AgentSourceInput>[
    AgentSourceInput(
      id: 'src-1',
      kind: AgentSourceKind.userText,
      text: '何卒宜しく',
    ),
  ],
);

AgentCitation _citation({
  required String id,
  required String entryKey,
  required String snippet,
  String dictionaryId = 'dict-a',
  int order = 0,
}) {
  return AgentCitation(
    id: id,
    kind: 'mdict',
    dictionaryId: dictionaryId,
    dictionaryTitle: dictionaryId,
    dictionaryOrder: order,
    entryKey: entryKey,
    headword: entryKey,
    snippet: snippet,
    toolCallId: 'call-1',
  );
}

AgentEvidenceBundle _evidence(List<AgentCitation> citations) {
  return AgentEvidenceBundle(
    sources: const <AgentSourceEvidence>[
      AgentSourceEvidence(
        id: 'src-1',
        kind: 'user_text',
        text: '何卒宜しく',
        tokens: <AgentTokenEvidence>[
          AgentTokenEvidence(
            id: 't1',
            surface: '何卒',
            reading: 'なにとぞ',
            lemma: '何卒',
            start: 0,
            end: 2,
            content: true,
            citationIds: <String>['source-1'],
          ),
          AgentTokenEvidence(
            id: 't2',
            surface: '宜しく',
            reading: 'よろしく',
            lemma: '宜しい',
            start: 2,
            end: 5,
            content: true,
          ),
        ],
      ),
    ],
    citations: citations,
    budget: AgentEvidenceBudget(
      uniqueTargets: 2,
      citations: citations.length,
      maxTargets: 120,
      maxCitations: 60,
    ),
  );
}

AgentCoverageReview _review({
  required List<AgentCoverageMissing> missing,
  List<AgentCoverageDuplicateGroup> groups =
      const <AgentCoverageDuplicateGroup>[],
}) {
  return AgentCoverageReview(
    sourceId: 'src-1',
    verdict: AgentCoverageVerdict.missing,
    missing: missing,
    duplicateGroups: groups,
  );
}

void main() {
  test('parses a valid coverage review', () {
    final parsed = parseCoverageReview('''
{"schema":"rikai.agent.coverage.v1","source_id":"src-1","verdict":"missing",
 "missing":[{"kind":"word","query":"何卒","source_refs":["t1"],
             "reason":"缺少用法","priority":1}],
 "duplicate_groups":[]}
''', expectedSourceId: 'src-1');
    expect(parsed.errors, isEmpty);
    expect(parsed.review?.missing.single.query, '何卒');
    expect(parsed.review?.missing.single.kind, AgentCoverageKind.word);
  });

  test('rejects a coverage review with a wrong schema', () {
    final parsed = parseCoverageReview(
      '{"schema":"wrong","source_id":"src-1","verdict":"sufficient",'
      '"missing":[],"duplicate_groups":[]}',
      expectedSourceId: 'src-1',
    );
    expect(parsed.review, isNull);
    expect(parsed.errors, isNotEmpty);
  });

  test('drops untraceable queries and unknown source refs', () {
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: '何卒',
            sourceRefs: <String>['t1'],
            reason: 'ok',
          ),
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: '存在しない語',
            sourceRefs: <String>['t1'],
            reason: 'not traceable',
          ),
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: '何卒',
            sourceRefs: <String>['x9'],
            reason: 'bad ref',
          ),
        ],
      ),
      input: _input,
      evidence: _evidence(const <AgentCitation>[]),
      limits: AgentLimits.standard,
    );
    expect(validated.missing, hasLength(1));
    expect(validated.missing.single.query, '何卒');
    expect(validated.droppedMissing, 2);
  });

  test('verifies duplicate groups with overlapping snippets locally', () {
    final keep = _citation(
      id: 'source-1',
      entryKey: '何卒',
      snippet: 'なにとぞ。どうか。正式な依頼に使う表現。',
    );
    final remove = _citation(
      id: 'source-2',
      entryKey: '何卒（副）',
      snippet: 'なにとぞ。どうか。',
    );
    final denser = _citation(
      id: 'source-3',
      entryKey: '何卒（別）',
      snippet: 'なにとぞ。どうか。正式な依頼に使う表現。さらに詳しい説明。',
    );
    final otherDictionary = _citation(
      id: 'source-4',
      entryKey: '何卒（他）',
      snippet: 'なにとぞ。どうか。',
      dictionaryId: 'dict-b',
      order: 1,
    );
    final evidence = _evidence(<AgentCitation>[
      keep,
      remove,
      denser,
      otherDictionary,
    ]);

    final removed = verifyCoverageDuplicates(
      evidence: evidence,
      groups: const <AgentCoverageDuplicateGroup>[
        AgentCoverageDuplicateGroup(
          dictionaryId: 'dict-a',
          keepEntryKey: '何卒',
          removeEntryKeys: <String>['何卒（副）', '何卒（別）'],
          reason: 'overlap',
        ),
      ],
    );

    expect(removed, <String>{'source-2'});
  });

  test('merges supplementary citations into the referenced token', () {
    final base = _evidence(<AgentCitation>[
      _citation(id: 'source-1', entryKey: '何卒', snippet: 'なにとぞ。'),
    ]);
    final extra = _citation(
      id: 'source-2',
      entryKey: '何卒（用法）',
      snippet: '正式な依頼に使う。',
    );
    final merged = mergeCoverageEvidence(
      evidence: base,
      citationsByQuery: <String, List<AgentCitation>>{
        '何卒': <AgentCitation>[extra],
      },
      missing: const <AgentCoverageMissing>[
        AgentCoverageMissing(
          kind: AgentCoverageKind.usage,
          query: '何卒',
          sourceRefs: <String>['t1'],
          reason: '缺少用法',
        ),
      ],
      limits: AgentLimits.standard,
    );

    expect(merged.citations, hasLength(2));
    expect(
      merged.sources.single.tokens.first.citationIds,
      contains('source-2'),
    );
  });

  test('prunes removed citations from tokens, patterns and the bundle', () {
    final base = _evidence(<AgentCitation>[
      _citation(id: 'source-1', entryKey: '何卒', snippet: 'a'),
      _citation(id: 'source-2', entryKey: '何卒（副）', snippet: 'b'),
    ]);
    final pruned = pruneCoverageCitations(
      evidence: base,
      removeIds: const <String>{'source-1'},
      limits: AgentLimits.standard,
    );

    expect(pruned.citations.map((citation) => citation.id), <String>[
      'source-2',
    ]);
    expect(
      pruned.sources.single.tokens.first.citationIds,
      isNot(contains('source-1')),
    );
  });
}
