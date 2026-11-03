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
    features[7] = surface;
    features[8] = surface;
    features[20] = surface;
    return Token.fromFeatures(
      surface: surface,
      features: features,
      start: start,
      end: end,
    );
  }
}

class _BatchLookup implements LookupPort, BatchLookupPort {
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
            LookupEntry(
              matchedKey: request.query,
              headword: request.query,
              html: '<p>${request.query}の説明</p>',
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
}
