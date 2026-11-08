import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/models/agent/agent_tool.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_match_mode.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/citation_registry.dart';
import 'package:rikai_mobile/services/agent/evidence_builder.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';

const _dictionaryA = DictionaryInfo(
  id: 'a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);
const _dictionaryB = DictionaryInfo(
  id: 'b',
  title: 'B',
  mdxPath: '/b.mdx',
  order: 1,
);

class _FakeTokenize implements TokenizePort {
  _FakeTokenize(this.tokens);

  final List<Token> tokens;

  @override
  Future<List<Token>> analyze(String text) async => tokens;
}

class _ThrowingTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    throw const AgentCapabilityException(
      AgentToolErrorCode.unidicNotReady,
      '尚未配置 UniDic',
    );
  }
}

class _ThrowingLookup implements LookupPort {
  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    throw StateError('dictionary worker failed');
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    throw StateError('dictionary worker failed');
  }
}

class _FakeLookup implements LookupPort {
  int calls = 0;

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    calls++;
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: _dictionaryB,
          entries: const <LookupEntry>[
            LookupEntry(matchedKey: '何卒', headword: '何卒', html: '<b>なにとぞ</b>'),
          ],
        ),
        DictionaryLookupGroup(
          dictionary: _dictionaryA,
          entries: const <LookupEntry>[
            LookupEntry(matchedKey: '何卒', headword: '何卒', html: '<b>なにとぞ</b>'),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    return const <String>[];
  }
}

/// Every dictionary returns [entriesPerDictionary] entries for every lookup.
/// The entry keys include the requested surface so different targets do not
/// dedupe into one citation.
class _OpaqueTitleLookup implements LookupPort {
  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: _dictionaryA,
          entries: const <LookupEntry>[
            LookupEntry(
              matchedKey: '01570 03798',
              headword: '01570 03798',
              html: '<div>今いま【今】［名］現在の時点。</div>',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    return const <String>[];
  }
}

class _AllHitsLookup implements LookupPort {
  _AllHitsLookup(this.entriesPerDictionary);

  final int entriesPerDictionary;
  final List<LookupMatchMode> modes = <LookupMatchMode>[];
  final List<String> queries = <String>[];

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    modes.add(request.matchMode);
    queries.add(request.query);
    final base = request.rawCandidates.firstWhere(
      (value) => value != '*' && value.trim().isNotEmpty,
      orElse: () => request.query,
    );
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        for (final dictionary in request.dictionaries)
          DictionaryLookupGroup(
            dictionary: dictionary,
            entries: <LookupEntry>[
              for (var index = 0; index < entriesPerDictionary; index++)
                LookupEntry(
                  matchedKey: '${dictionary.id}:$base:$index',
                  headword: '${dictionary.id}:$base:$index',
                  html: '<b>$base</b>',
                ),
            ],
          ),
      ],
    );
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    return const <String>[];
  }
}

class _ModeLookup implements LookupPort {
  _ModeLookup(this.entriesByMode, {this.onLookup, this.entriesForRequest});

  final Map<LookupMatchMode, List<String>> entriesByMode;
  final void Function(LookupRequest request)? onLookup;
  final List<String> Function(LookupRequest request)? entriesForRequest;
  final List<LookupMatchMode> modes = <LookupMatchMode>[];

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    modes.add(request.matchMode);
    onLookup?.call(request);
    final keys =
        entriesForRequest?.call(request) ??
        entriesByMode[request.matchMode] ??
        const <String>[];
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: <LookupEntry>[
            for (final key in keys)
              LookupEntry(matchedKey: key, headword: key, html: '<b>$key</b>'),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    return const <String>[];
  }
}

Token _token(String surface, int start) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = '副詞';
  features[7] = surface;
  features[8] = surface;
  features[20] = 'ナニトゾ';
  return Token.fromFeatures(
    surface: surface,
    features: features,
    start: start,
    end: start + surface.length,
  );
}

Token _tokenWithPos(String surface, String pos, int start) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = pos;
  features[7] = surface;
  features[8] = surface;
  features[10] = surface;
  features[20] = surface;
  return Token.fromFeatures(
    surface: surface,
    features: features,
    start: start,
    end: start + surface.length,
  );
}

AgentSourceInput _source(String text) =>
    AgentSourceInput(id: 'src-1', kind: AgentSourceKind.userText, text: text);

void main() {
  test(
    'builds one citation per target and sorts by dictionary order',
    () async {
      final citations = CitationRegistry();
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0), _token('宜しく', 3)]),
        lookupPort: _AllHitsLookup(1),
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: citations,
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[_source('何卒宜しく')],
        dictionaries: const <DictionaryInfo>[_dictionaryB, _dictionaryA],
      );

      // Target 0 starts at dictionary A (order 0), target 1 starts at B.
      expect(bundle.citations, hasLength(2));
      expect(bundle.citations.first.dictionaryOrder, 0);
      expect(bundle.citations.last.dictionaryOrder, 1);
      expect(bundle.sources.single.tokens, hasLength(2));
      expect(bundle.sources.single.tokens.first.citationIds, hasLength(1));
      expect(bundle.sources.single.tokens.last.citationIds, hasLength(1));
      expect(bundle.budget.uniqueTargets, 2);
      expect(bundle.truncated, isFalse);
    },
  );

  test('derives a readable citation title from entry HTML', () async {
    final citations = CitationRegistry();
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('今', 0)]),
      lookupPort: _OpaqueTitleLookup(),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: citations,
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('今')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    final citation = bundle.citations.single;
    // The internal key stays available for exact lookup/navigation, while the
    // user-facing headword is extracted from the entry HTML.
    expect(citation.entryKey, '01570 03798');
    expect(citation.headword, '今');
    expect(citation.displayTitle, '今');
    expect(jsonEncode(bundle.toJson()), isNot(contains('"headword":"01570')));
  });

  test('keeps UniDic pitch local and out of the provider JSON', () async {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '名詞';
    features[7] = '橋';
    features[8] = '橋';
    features[20] = 'ハシ';
    features[24] = '2';
    final token = Token.fromFeatures(
      surface: '橋',
      features: features,
      start: 0,
      end: 1,
    );
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[token]),
      lookupPort: _FakeLookup(),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('橋')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(bundle.pitchAccents['t1']?.moraPattern, 'LH');
    expect(jsonEncode(bundle.toJson()), isNot(contains('pitch')));
  });

  test('truncates when the unique target budget is exceeded', () async {
    final citations = CitationRegistry();
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0), _token('宜しく', 2)]),
      lookupPort: _FakeLookup(),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: citations,
      limits: const AgentLimits(maxTargets: 1),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒宜しく')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(bundle.truncated, isTrue);
    expect(bundle.budget.uniqueTargets, 1);
    expect(bundle.sources.single.tokens.last.citationIds, isEmpty);
  });

  test(
    'a failing dictionary is recorded instead of silently swallowed',
    () async {
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
        lookupPort: _ThrowingLookup(),
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: CitationRegistry(),
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[_source('何卒')],
        dictionaries: const <DictionaryInfo>[_dictionaryA],
      );

      expect(bundle.dictionaryIssues, hasLength(1));
      expect(bundle.dictionaryIssues.single.dictionaryId, 'a');
      expect(
        bundle.dictionaryIssues.single.code,
        AgentToolErrorCode.dictionaryLookupFailed.wireName,
      );
    },
  );

  test('a missing UniDic falls back to raw surface lookup', () async {
    final builder = EvidenceBuilder(
      tokenizePort: _ThrowingTokenize(),
      lookupPort: _FakeLookup(),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(bundle.structureUnavailable, isTrue);
    expect(bundle.sources.single.tokens, isEmpty);
    expect(bundle.citations, isNotEmpty);
  });

  test(
    'breadth pass tries modes in exact→prefix→suffix→incremental order',
    () async {
      final lookup = _ModeLookup(<LookupMatchMode, List<String>>{
        LookupMatchMode.exact: <String>[],
        LookupMatchMode.prefix: <String>[],
        LookupMatchMode.suffix: <String>[],
        LookupMatchMode.incremental: <String>['incremental'],
      });
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
        lookupPort: lookup,
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: CitationRegistry(),
        limits: const AgentLimits(maxEntriesPerDictionary: 10),
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[_source('何卒')],
        dictionaries: const <DictionaryInfo>[_dictionaryA],
      );

      expect(lookup.modes, <LookupMatchMode>[
        LookupMatchMode.exact,
        LookupMatchMode.prefix,
        LookupMatchMode.suffix,
        LookupMatchMode.incremental,
      ]);
      expect(bundle.citations, hasLength(1));
    },
  );

  test('stops immediately when the global citation limit is reached', () async {
    final lookup = _ModeLookup(<LookupMatchMode, List<String>>{
      LookupMatchMode.exact: <String>['exact'],
      LookupMatchMode.prefix: <String>['prefix'],
    });
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0), _token('宜しく', 2)]),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(
        maxEvidenceEntries: 1,
        maxEntriesPerDictionary: 10,
      ),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒宜しく')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(lookup.modes, <LookupMatchMode>[
      LookupMatchMode.exact,
      LookupMatchMode.exact,
    ]);
    expect(bundle.citations, hasLength(1));
    expect(bundle.truncated, isTrue);
  });

  test('stops later modes once a target has a citation', () async {
    final lookup = _ModeLookup(<LookupMatchMode, List<String>>{
      LookupMatchMode.exact: <String>[],
      LookupMatchMode.prefix: <String>[],
      LookupMatchMode.suffix: <String>['suffix'],
      LookupMatchMode.incremental: <String>['incremental'],
    });
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(
        maxEntriesPerDictionary: 10,
        enableDepthPass: true,
      ),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    // suffix found the first hit; incremental must not run for this target.
    expect(lookup.modes, <LookupMatchMode>[
      LookupMatchMode.exact,
      LookupMatchMode.prefix,
      LookupMatchMode.suffix,
    ]);
    // One breadth entry per dictionary; depth is not reached because the
    // dynamic short-text limit is already satisfied.
    expect(bundle.citations, hasLength(1));
  });

  test('later lookup modes skip function-word targets', () async {
    final calls = <({String query, LookupMatchMode mode})>[];
    final lookup = _ModeLookup(
      <LookupMatchMode, List<String>>{
        LookupMatchMode.exact: <String>[],
        LookupMatchMode.prefix: <String>[],
      },
      entriesForRequest: (request) =>
          request.matchMode == LookupMatchMode.prefix && request.query == '何卒'
          ? <String>['何卒']
          : <String>[],
      onLookup: (request) =>
          calls.add((query: request.query, mode: request.matchMode)),
    );
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[
        _tokenWithPos('何卒', '副詞', 0),
        _tokenWithPos('は', '助詞', 2),
      ]),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(maxEntriesPerDictionary: 10),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒は')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(
      calls
          .where((call) => call.mode == LookupMatchMode.prefix)
          .map((call) => call.query),
      <String>['何卒'],
    );
    expect(bundle.citations, hasLength(1));
    expect(bundle.sources.single.tokens.last.citationIds, isEmpty);
  });

  test('coverage extra lookup continues past an empty mode', () async {
    final lookup = _ModeLookup(<LookupMatchMode, List<String>>{
      LookupMatchMode.exact: <String>[],
      LookupMatchMode.prefix: <String>[],
      LookupMatchMode.suffix: <String>['extra'],
    });
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(maxEntriesPerDictionary: 10),
    );

    final result = await builder.lookupExtraQueries(
      queries: const <String>['何卒'],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
      maxNewCitations: 5,
    );

    expect(lookup.modes, <LookupMatchMode>[
      LookupMatchMode.exact,
      LookupMatchMode.prefix,
      LookupMatchMode.suffix,
    ]);
    expect(result['何卒'], hasLength(1));
  });

  test('breadth grants one entry per target and skips later modes', () async {
    final lookup = _AllHitsLookup(3);
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(maxEntriesPerDictionary: 3),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒')],
      dictionaries: const <DictionaryInfo>[_dictionaryA, _dictionaryB],
    );

    expect(lookup.modes, <LookupMatchMode>[LookupMatchMode.exact]);
    expect(bundle.citations, hasLength(1));
    expect(bundle.budget.maxCitations, 7);
  });

  test('cancellation stops between lookup modes', () async {
    var cancelled = false;
    final lookup = _ModeLookup(
      <LookupMatchMode, List<String>>{
        LookupMatchMode.exact: <String>['exact'],
        LookupMatchMode.prefix: <String>['prefix'],
      },
      onLookup: (request) {
        if (request.matchMode == LookupMatchMode.exact) cancelled = true;
      },
    );
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(maxEntriesPerDictionary: 10),
    );

    await expectLater(
      builder.build(
        sources: <AgentSourceInput>[_source('何卒')],
        dictionaries: const <DictionaryInfo>[_dictionaryA],
        isCancelled: () => cancelled,
      ),
      throwsA(
        isA<AgentCapabilityException>().having(
          (error) => error.code,
          'code',
          AgentToolErrorCode.toolCancelled,
        ),
      ),
    );
    expect(lookup.modes, <LookupMatchMode>[LookupMatchMode.exact]);
  });

  test(
    'sample-like short text stays under 15 citations and runs exact only',
    () async {
      const source = 'それは人のくべたのろいだとしても。';
      final tokens = <Token>[
        _tokenWithPos('それ', '代名詞', 0),
        _tokenWithPos('は', '助詞', 2),
        _tokenWithPos('人', '名詞', 3),
        _tokenWithPos('の', '助詞', 4),
        _tokenWithPos('くべ', '動詞', 5),
        _tokenWithPos('た', '助動詞', 7),
        _tokenWithPos('のろい', '名詞', 8),
        _tokenWithPos('だ', '助動詞', 11),
        _tokenWithPos('として', '助詞', 12),
        _tokenWithPos('も', '助詞', 15),
        _tokenWithPos('。', '補助記号', 16),
      ];
      final lookup = _AllHitsLookup(3);
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(tokens),
        lookupPort: lookup,
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: CitationRegistry(),
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[_source(source)],
        dictionaries: const <DictionaryInfo>[_dictionaryA, _dictionaryB],
      );

      // One breadth entry per content target; the reserve is only for coverage.
      expect(bundle.citations.length, lessThanOrEqualTo(15));
      expect(bundle.citations, hasLength(3));
      expect(bundle.budget.maxCitations, 9);
      expect(bundle.truncated, isFalse);
      // Exact found the content words, so no prefix/suffix/incremental scans.
      expect(
        lookup.modes.every((mode) => mode == LookupMatchMode.exact),
        isTrue,
      );
      // Punctuation is context only and never enters the lookup list.
      expect(lookup.queries, isNot(contains('。')));
      final punctuation = bundle.sources.single.tokens.firstWhere(
        (token) => token.surface == '。',
      );
      expect(punctuation.citationIds, isEmpty);
      for (final surface in const <String>['人', 'くべ', 'のろい']) {
        final token = bundle.sources.single.tokens.firstWhere(
          (token) => token.surface == surface,
        );
        expect(token.citationIds, hasLength(1));
      }
    },
  );

  test(
    'rotates the primary dictionary per target so dictionaries are shared',
    () async {
      final dictionaries = <DictionaryInfo>[
        for (var index = 0; index < 5; index++)
          DictionaryInfo(
            id: 'd$index',
            title: 'D$index',
            mdxPath: '/d$index.mdx',
            order: index,
          ),
      ];
      final tokens = <Token>[
        for (var index = 0; index < 10; index++) _token('語$index', index * 3),
      ];
      final citations = CitationRegistry();
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(tokens),
        lookupPort: _AllHitsLookup(3),
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: citations,
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[
          _source(List<String>.generate(10, (index) => '語$index').join()),
        ],
        dictionaries: dictionaries,
      );

      final counts = <String, int>{};
      for (final citation in bundle.citations) {
        counts.update(
          citation.dictionaryId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      expect(bundle.citations, hasLength(10));
      // 10 content targets + the coverage reserve, not 10 × 5 dictionaries.
      expect(bundle.budget.maxCitations, 16);
      for (final dictionary in dictionaries) {
        expect(
          counts[dictionary.id],
          2,
          reason: '${dictionary.id} should receive a fair share of citations',
        );
      }
      expect(
        bundle.sources.single.tokens.every(
          (token) => token.citationIds.isNotEmpty,
        ),
        isTrue,
      );
      expect(bundle.truncated, isFalse);
    },
  );

  test(
    'interleaves targets across quotes before front-loading a sentence',
    () async {
      final lookup = _AllHitsLookup(1);
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(<Token>[
          _tokenWithPos('何卒', '名詞', 0),
          _tokenWithPos('宜しく', '形容詞', 2),
          _tokenWithPos('今日', '名詞', 6),
          _tokenWithPos('天気', '名詞', 8),
        ]),
        lookupPort: lookup,
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: CitationRegistry(),
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[_source('何卒宜しく。今日天気。')],
        dictionaries: const <DictionaryInfo>[_dictionaryA, _dictionaryB],
        quotes: const <AgentQuoteRef>[
          AgentQuoteRef(
            id: 'q1',
            sourceId: 'src-1',
            start: 0,
            end: 5,
            text: '何卒宜しく',
            origin: AgentQuoteOrigin.userText,
          ),
          AgentQuoteRef(
            id: 'q2',
            sourceId: 'src-1',
            start: 6,
            end: 10,
            text: '今日天気',
            origin: AgentQuoteOrigin.userText,
          ),
        ],
      );

      // q1 first target, q2 first target, then q1/q2 second targets.
      expect(lookup.queries, <String>['何卒', '今日', '宜しく', '天気']);
      expect(bundle.citations, hasLength(4));
    },
  );

  test('depth pass is opt-in and can add extra senses', () async {
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0)]),
      lookupPort: _AllHitsLookup(3),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(
        maxEntriesPerDictionary: 3,
        enableDepthPass: true,
      ),
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(bundle.citations, hasLength(3));
  });

  test('coverage supplements rotate the starting dictionary too', () async {
    final dictionaries = <DictionaryInfo>[
      for (var index = 0; index < 5; index++)
        DictionaryInfo(
          id: 'd$index',
          title: 'D$index',
          mdxPath: '/d$index.mdx',
          order: index,
        ),
    ];
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(const <Token>[]),
      lookupPort: _AllHitsLookup(3),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
    );

    final result = await builder.lookupExtraQueries(
      queries: const <String>['補足一', '補足二'],
      dictionaries: dictionaries,
      maxNewCitations: 2,
    );

    final dictionariesUsed = <String>[
      for (final query in const <String>['補足一', '補足二'])
        for (final citation in result[query]!) citation.dictionaryId,
    ];
    expect(dictionariesUsed, <String>['d0', 'd1']);
  });
}
