import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/citation_registry.dart';
import 'package:rikai_mobile/services/agent/evidence_builder.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

class _ThreeTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    return <Token>[
      _token('何卒', 0, 2),
      _token('今日', 2, 4),
      _token('天気', 4, 6),
    ];
  }

  Token _token(String surface, int start, int end) {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '名詞';
    for (final index in <int>[7, 8, 9, 10, 12, 13, 20]) {
      features[index] = surface;
    }
    return Token.fromFeatures(
      surface: surface,
      features: features,
      start: start,
      end: end,
    );
  }
}

class _BatchLookup implements LookupPort, BatchLookupPort {
  _BatchLookup({this.entriesPerRequest = 1});

  final int entriesPerRequest;
  int singleCalls = 0;
  final List<int> batchSizes = <int>[];

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    singleCalls++;
    return _resultFor(request);
  }

  @override
  Future<List<LookupResult>> lookupMany(List<LookupRequest> requests) async {
    batchSizes.add(requests.length);
    return <LookupResult>[
      for (final request in requests) _resultFor(request),
    ];
  }

  LookupResult _resultFor(LookupRequest request) {
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: <LookupEntry>[
            for (var index = 1; index <= entriesPerRequest; index++)
              LookupEntry(
                matchedKey: '${request.query}-$index',
                headword: '${request.query}-$index',
                html: '<p>${request.query}の説明$index</p>',
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

void main() {
  test('batches evidence lookups through BatchLookupPort', () async {
    final lookup = _BatchLookup();
    final builder = EvidenceBuilder(
      tokenizePort: _ThreeTokenize(),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(
        maxCoverageFallback: 0,
        enableRichTextPostProcess: false,
      ),
    );

    final evidence = await builder.build(
      sources: const <AgentSourceInput>[
        AgentSourceInput(
          id: 'src-1',
          kind: AgentSourceKind.userText,
          text: '何卒今日天気',
        ),
      ],
      dictionaries: const <DictionaryInfo>[_dictionary],
    );

    expect(lookup.singleCalls, 0);
    expect(lookup.batchSizes, isNotEmpty);
    expect(lookup.batchSizes.first, 3);
    expect(evidence.citations, isNotEmpty);
    expect(evidence.budget.citations, evidence.citations.length);
  });

  test('breadth pass gives each target a citation before extra senses', () async {
    final lookup = _BatchLookup(entriesPerRequest: 3);
    final builder = EvidenceBuilder(
      tokenizePort: _ThreeTokenize(),
      lookupPort: lookup,
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: CitationRegistry(),
      limits: const AgentLimits(
        maxEvidenceEntries: 2,
        maxEntriesPerDictionary: 3,
        maxCoverageFallback: 0,
        enableRichTextPostProcess: false,
      ),
    );

    final evidence = await builder.build(
      sources: const <AgentSourceInput>[
        AgentSourceInput(
          id: 'src-1',
          kind: AgentSourceKind.userText,
          text: '何卒今日天気',
        ),
      ],
      dictionaries: const <DictionaryInfo>[_dictionary],
    );

    // The old target-by-target 3-entry fetch filled both slots with 何卒.
    // Breadth-first keeps one hit for the first two targets.
    expect(evidence.citations, hasLength(2));
    expect(
      evidence.citations.map((citation) => citation.entryKey),
      containsAll(<String>['何卒-1', '今日-1']),
    );
    expect(
      evidence.citations.map((citation) => citation.entryKey),
      isNot(contains('天気-1')),
    );
  });
}
