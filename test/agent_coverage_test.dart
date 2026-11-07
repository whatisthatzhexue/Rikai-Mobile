import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_coverage.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/services/agent/agent_coverage_parser.dart';
import 'package:rikai_mobile/services/agent/agent_prompts.dart';
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
  String matchedKey = '',
}) {
  return AgentCitation(
    id: id,
    kind: 'mdict',
    dictionaryId: dictionaryId,
    dictionaryTitle: dictionaryId,
    dictionaryOrder: order,
    entryKey: entryKey,
    matchedKey: matchedKey,
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

AgentTokenEvidence _token(String id, String surface, int start, int end) {
  return AgentTokenEvidence(
    id: id,
    surface: surface,
    start: start,
    end: end,
    content: true,
  );
}

AgentEvidenceBundle _evidenceFor(
  String text,
  List<AgentTokenEvidence> tokens, {
  List<AgentCitation> citations = const <AgentCitation>[],
  List<AgentGrammarPatternEvidence> patterns =
      const <AgentGrammarPatternEvidence>[],
  bool structureUnavailable = false,
}) {
  return AgentEvidenceBundle(
    sources: <AgentSourceEvidence>[
      AgentSourceEvidence(
        id: 'src-1',
        kind: 'user_text',
        text: text,
        tokens: tokens,
      ),
    ],
    patterns: patterns,
    citations: citations,
    structureUnavailable: structureUnavailable,
    budget: AgentEvidenceBudget(
      uniqueTargets: tokens.length + patterns.length,
      citations: citations.length,
      maxTargets: 120,
      maxCitations: 60,
    ),
  );
}

void main() {
  test('coverage budget is derived from its own MISSING/duplicate limits', () {
    const limits = AgentLimits.standard;
    final standard = limits.coverageReviewMaxTokens;
    final smaller = const AgentLimits(
      maxCoverageMissing: 5,
      maxCoverageDuplicateGroups: 2,
    ).coverageReviewMaxTokens;
    expect(standard, greaterThan(4096));
    expect(smaller, lessThan(standard));
    expect(smaller, greaterThan(1024));

    final expectedChars =
        AgentLimits.coverageRootAndNotesChars +
        limits.maxCoverageMissing *
            (limits.maxCoverageQueryChars +
                AgentLimits.coverageRefsChars +
                AgentLimits.coverageReasonChars +
                AgentLimits.coverageTagChars) +
        limits.maxCoverageDuplicateGroups *
            (AgentLimits.coverageDuplicateKeyChars +
                AgentLimits.coverageReasonChars +
                AgentLimits.coverageTagChars);
    expect(
      standard,
      (expectedChars / AgentLimits.coverageCharsPerToken).ceil() +
          AgentLimits.coverageSafetyTokens,
    );
    // Coverage reasons are frequently Chinese/Japanese, where some tokenizers
    // approach one UTF-16 code unit per token. The coefficient must stay at or
    // below 1.0 so the derived ceiling does not undercount.
    expect(AgentLimits.coverageCharsPerToken, lessThanOrEqualTo(1.0));
  });

  test('coverage prompt is compact and keeps its configured output budget', () {
    final request = buildCoverageRequest(
      model: 'small',
      language: AgentResponseLanguage.chinese,
      input: _input,
      evidence: _evidence(<AgentCitation>[
        _citation(
          id: 'source-1',
          entryKey: '何卒',
          matchedKey: '何卒・一致',
          snippet: 'なにとぞ。',
        ),
      ]),
      userRequest: '解释这句话',
    );
    expect(request.maxTokens, AgentLimits.standard.coverageReviewMaxTokens);
    final text = request.messages.map((message) => message.text).join('\n');
    expect(text, contains('"tokens"'));
    expect(text, isNot(contains('"start":')));
    expect(text, isNot(contains('"end":')));
    expect(text, contains('"citations"'));
    expect(text, contains('"entry_key":"何卒"'));
    expect(text, isNot(contains('"matched_key"')));
    expect(text, isNot(contains('"variants"')));
    expect(text, isNot(contains('"lookup_candidates"')));
  });

  test('analysis prompt omits punctuation token objects', () {
    final request = buildAnalysisRequest(
      model: 'large',
      mode: AgentMode.strict,
      responseLanguage: AgentResponseLanguage.chinese,
      input: _input,
      evidence: _evidenceFor('何卒。', <AgentTokenEvidence>[
        _token('t1', '何卒', 0, 2),
        const AgentTokenEvidence(
          id: 't2',
          surface: '。',
          pos: '補助記号・句点',
          start: 2,
          end: 3,
        ),
      ]),
      quotes: const <AgentQuoteRef>[],
      dictionaryProfiles: const <String>[],
      userRequest: '解释这句话',
    );
    final text = request.messages.map((message) => message.text).join('\n');
    expect(text, contains('"id":"t1"'));
    expect(text, isNot(contains('"id":"t2"')));
  });

  test('coverage prompt omits punctuation token objects', () {
    final request = buildCoverageRequest(
      model: 'small',
      language: AgentResponseLanguage.chinese,
      input: _input,
      evidence: _evidenceFor('何卒。', <AgentTokenEvidence>[
        _token('t1', '何卒', 0, 2),
        const AgentTokenEvidence(
          id: 't2',
          surface: '。',
          pos: '補助記号・句点',
          start: 2,
          end: 3,
        ),
      ]),
      userRequest: '解释这句话',
    );
    final text = request.messages.map((message) => message.text).join('\n');
    expect(text, contains('"id":"t1"'));
    expect(text, isNot(contains('"id":"t2"')));
  });

  test('coverage prompt documents compound MISSING expansion', () {
    final prompt = coverageSystemPrompt(AgentResponseLanguage.chinese);
    expect(prompt, contains('contiguous compound or fixed collocation'));
    expect(prompt, contains('ところが'));
    expect(prompt, contains('never request a whole'));
    expect(prompt, contains('sentence or a paraphrase'));
  });

  test('parses a valid coverage review', () {
    final parsed = parseCoverageReview('''
[COVERAGE verdict="missing"]
[MISSING kind="word" query="何卒" refs="t1" priority="1"]缺少用法[/MISSING]
[DUPLICATE dictionary="dict-a" keep="何卒" remove="何卒（副）|何卒（別）"]重复[/DUPLICATE]
[NOTES]short note[/NOTES]
[/COVERAGE]
''', expectedSourceId: 'src-1');
    expect(parsed.errors, isEmpty);
    expect(parsed.review?.missing.single.query, '何卒');
    expect(parsed.review?.missing.single.kind, AgentCoverageKind.word);
    expect(parsed.review?.missing.single.priority, 1);
    expect(parsed.review?.duplicateGroups.single.keepEntryKey, '何卒');
    expect(parsed.review?.duplicateGroups.single.removeEntryKeys, <String>[
      '何卒（副）',
      '何卒（別）',
    ]);
    expect(parsed.review?.notes, 'short note');
  });

  test('keeps spaces inside duplicate entry keys', () {
    final parsed = parseCoverageReview('''
[COVERAGE verdict="missing"]
[DUPLICATE dictionary="dict-a" keep="take care" remove="take care of|look after"]重复[/DUPLICATE]
[/COVERAGE]
''', expectedSourceId: 'src-1');
    expect(parsed.errors, isEmpty);
    expect(parsed.review?.duplicateGroups.single.keepEntryKey, 'take care');
    expect(parsed.review?.duplicateGroups.single.removeEntryKeys, <String>[
      'take care of',
      'look after',
    ]);
  });

  test(
    'parses sufficient reviews, including empty unclosed/self-closing tags',
    () {
      for (final raw in <String>[
        '[COVERAGE verdict="sufficient"][/COVERAGE]',
        '[COVERAGE verdict="sufficient"]',
        '[COVERAGE verdict="sufficient" /]',
        '```text\n[COVERAGE verdict="sufficient"][/COVERAGE]\n```',
      ]) {
        final normalized = normalizeCoverageResponseText(raw);
        expect(
          normalizeCoverageResponseText(normalized),
          normalized,
          reason: 'normalization must be idempotent: $raw',
        );
        final parsed = parseCoverageReview(raw, expectedSourceId: 'src-1');
        expect(parsed.errors, isEmpty, reason: raw);
        expect(parsed.review?.verdict, AgentCoverageVerdict.sufficient);
        expect(parsed.review?.missing, isEmpty);
        expect(parsed.normalizedText, normalized);
      }
    },
  );

  test('a sufficient verdict ignores stray item blocks', () {
    final parsed = parseCoverageReview(
      '[COVERAGE verdict="sufficient"]\n'
      '[MISSING kind="word" query="何卒" refs="t1"]x[/MISSING]\n'
      '[/COVERAGE]',
      expectedSourceId: 'src-1',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.review?.verdict, AgentCoverageVerdict.sufficient);
    expect(parsed.review?.missing, isEmpty);
  });

  test('one malformed missing item does not discard the whole review', () {
    final logs = <String>[];
    final parsed = parseCoverageReview(
      '''
[COVERAGE verdict="missing"]
[MISSING kind="word" query="" refs="t1"]bad[/MISSING]
[MISSING kind="vocabulary" query="何卒" refs="source-1" priority="99"]缺少用法[/MISSING]
[MISSING kind="grammar" query="のに" refs="p1"]缺少语法[/MISSING]
[DUPLICATE keep="何卒"]bad duplicate[/DUPLICATE]
[DUPLICATE dictionary="dict-a" keep="何卒" remove="何卒（副）"]重复[/DUPLICATE]
[/COVERAGE]
''',
      expectedSourceId: 'src-1',
      debugLog: logs.add,
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.review?.missing, hasLength(2));
    expect(parsed.review?.missing.first.kind, AgentCoverageKind.word);
    expect(parsed.review?.missing.first.sourceRefs, <String>['src-1']);
    expect(parsed.review?.missing.first.priority, 5);
    expect(parsed.review?.duplicateGroups, hasLength(1));

    // Automatic corrections must be visible in debug logs; they must not
    // silently rewrite model output.
    expect(logs, contains('dropped MISSING[0] query="" (chars=0)'));
    expect(logs, contains('normalized MISSING[1] kind="vocabulary" -> "word"'));
    expect(logs, contains('normalized MISSING[1] ref="source-1" -> "src-1"'));
    expect(logs, contains('normalized MISSING[1] priority="99" -> 5'));
    expect(
      logs,
      contains('dropped DUPLICATE[0] dictionary="" keep="何卒" removeCount=0'),
    );
  });

  test('rejects responses without a coverage root or with a bad verdict', () {
    for (final raw in <String>[
      'not coverage tags',
      '[COVERAGE verdict="missing"]\n[MISSING kind="word" query="何卒" refs="t1"]缺少用法[/MISSING]',
      '[COVERAGE verdict="missing"]\n[MISSING kind="word" query="何卒" refs="t1"]缺少用法',
      '[COVERAGE verdict="wrong"][/COVERAGE]',
    ]) {
      final parsed = parseCoverageReview(raw, expectedSourceId: 'src-1');
      expect(parsed.review, isNull, reason: raw);
      expect(parsed.errors, isNotEmpty, reason: raw);
    }
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

  test('accepts a compound query spanning a small token window', () {
    final evidence = _evidenceFor('ところが', <AgentTokenEvidence>[
      _token('t1', 'ところ', 0, 3),
      _token('t2', 'が', 3, 4),
    ]);
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: 'ところが',
            sourceRefs: <String>['t1', 't2'],
            reason: 'compound',
          ),
        ],
      ),
      input: _input,
      evidence: evidence,
      limits: AgentLimits.standard,
    );

    expect(validated.missing.map((item) => item.query), <String>['ところが']);
    expect(validated.droppedMissing, 0);
  });

  test('bounds unknown compound queries by token span, not characters', () {
    const text = 'あいうえおかき';
    final tokens = <AgentTokenEvidence>[
      for (var index = 0; index < text.length; index++)
        _token(
          't${index + 1}',
          text.substring(index, index + 1),
          index,
          index + 1,
        ),
    ];
    final validated = validateCoverageReview(
      review: _review(
        missing: <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: 'あいうえおか',
            sourceRefs: const <String>['t1', 't2', 't3', 't4', 't5', 't6'],
            reason: 'six tokens',
          ),
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: text,
            sourceRefs: const <String>[
              't1',
              't2',
              't3',
              't4',
              't5',
              't6',
              't7',
            ],
            reason: 'seven tokens',
          ),
        ],
      ),
      input: _input,
      evidence: _evidenceFor(text, tokens),
      limits: AgentLimits.standard,
    );

    expect(validated.missing.map((item) => item.query), <String>['あいうえおか']);
    expect(validated.droppedMissing, 1);
  });

  test('accepts a long query inside a single token', () {
    const text = 'あいうえおかきくけこさしすせそたちつてと';
    const query = 'あいうえおかきくけこさしすせそ';
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: query,
            sourceRefs: <String>['t1'],
            reason: 'long single token',
          ),
        ],
      ),
      input: _input,
      evidence: _evidenceFor(text, <AgentTokenEvidence>[
        _token('t1', text, 0, text.length),
      ]),
      limits: AgentLimits.standard,
    );

    expect(validated.missing.map((item) => item.query), <String>[query]);
    expect(validated.droppedMissing, 0);
  });

  test('accepts a multiword phrase when it spans few tokens', () {
    const text = 'take care of it';
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: 'take care of',
            sourceRefs: <String>['t1', 't2', 't3'],
            reason: 'multiword',
          ),
        ],
      ),
      input: _input,
      evidence: _evidenceFor(text, <AgentTokenEvidence>[
        _token('t1', 'take', 0, 4),
        _token('t2', 'care', 5, 9),
        _token('t3', 'of', 10, 12),
        _token('t4', 'it', 13, 15),
      ]),
      limits: AgentLimits.standard,
    );

    expect(validated.missing.map((item) => item.query), <String>[
      'take care of',
    ]);
    expect(validated.droppedMissing, 0);
  });

  test('drops a compound query containing a line break', () {
    const text = 'ところ\nが';
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: 'ところ\nが',
            sourceRefs: <String>['t1', 't2'],
            reason: 'line break',
          ),
        ],
      ),
      input: _input,
      evidence: _evidenceFor(text, <AgentTokenEvidence>[
        _token('t1', 'ところ', 0, 3),
        _token('t2', 'が', 4, 5),
      ]),
      limits: AgentLimits.standard,
    );

    expect(validated.missing, isEmpty);
    expect(validated.droppedMissing, 1);
  });

  test('without tokens only known terms bypass compound validation', () {
    final evidence = _evidenceFor(
      'ところが',
      const <AgentTokenEvidence>[],
      patterns: const <AgentGrammarPatternEvidence>[
        AgentGrammarPatternEvidence(
          id: 'p1',
          surface: 'ところ',
          tokenIds: <String>[],
          start: 0,
          end: 3,
        ),
      ],
    );
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: 'ところが',
            sourceRefs: <String>['src-1'],
            reason: 'unknown without tokens',
          ),
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: 'ところ',
            sourceRefs: <String>['p1'],
            reason: 'known pattern',
          ),
        ],
      ),
      input: _input,
      evidence: evidence,
      limits: AgentLimits.standard,
    );

    expect(validated.missing.map((item) => item.query), <String>['ところ']);
    expect(validated.droppedMissing, 1);
  });

  test('grammar queries are not limited by the compound token span', () {
    const text = 'あいうえおかきくけこ';
    final tokens = <AgentTokenEvidence>[
      for (var index = 0; index < text.length; index++)
        _token(
          't${index + 1}',
          text.substring(index, index + 1),
          index,
          index + 1,
        ),
    ];
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.grammar,
            query: text,
            sourceRefs: <String>[
              't1',
              't2',
              't3',
              't4',
              't5',
              't6',
              't7',
              't8',
              't9',
              't10',
            ],
            reason: 'grammar pattern',
          ),
        ],
      ),
      input: _input,
      evidence: _evidenceFor(text, tokens),
      limits: AgentLimits.standard,
    );

    expect(validated.missing.map((item) => item.query), <String>[text]);
    expect(validated.droppedMissing, 0);
  });

  test('skips coverage queries already covered by a citation', () {
    final validated = validateCoverageReview(
      review: _review(
        missing: const <AgentCoverageMissing>[
          AgentCoverageMissing(
            kind: AgentCoverageKind.word,
            query: '何卒',
            sourceRefs: <String>['t1'],
            reason: 'already covered',
          ),
          AgentCoverageMissing(
            kind: AgentCoverageKind.sense,
            query: '宜しく',
            sourceRefs: <String>['t2'],
            reason: 'a different sense is still missing',
          ),
        ],
      ),
      input: _input,
      evidence: _evidence(<AgentCitation>[
        _citation(id: 'source-1', entryKey: '何卒', snippet: 'なにとぞ。'),
      ]),
      limits: AgentLimits.standard,
    );

    expect(validated.missing, hasLength(1));
    expect(validated.missing.single.query, '宜しく');
    expect(validated.droppedMissing, 0);
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
