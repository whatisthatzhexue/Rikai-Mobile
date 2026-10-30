import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_tool.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
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

AgentSourceInput _source(String text) =>
    AgentSourceInput(id: 'src-1', kind: AgentSourceKind.userText, text: text);

void main() {
  test(
    'builds token citations, dedupes entries and sorts by dictionary order',
    () async {
      final citations = CitationRegistry();
      final builder = EvidenceBuilder(
        tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0), _token('何卒', 0)]),
        lookupPort: _FakeLookup(),
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: citations,
      );

      final bundle = await builder.build(
        sources: <AgentSourceInput>[_source('何卒何卒')],
        dictionaries: const <DictionaryInfo>[_dictionaryB, _dictionaryA],
      );

      expect(bundle.citations, hasLength(2));
      expect(bundle.citations.first.dictionaryOrder, 0);
      expect(bundle.citations.last.dictionaryOrder, 1);
      expect(bundle.sources.single.tokens, hasLength(2));
      expect(bundle.sources.single.tokens.first.citationIds, hasLength(2));
      expect(bundle.sources.single.tokens.last.citationIds, hasLength(2));
      expect(bundle.budget.uniqueTargets, 1);
      expect(bundle.truncated, isFalse);
    },
  );

  test('truncates when the unique target budget is exceeded', () async {
    final citations = CitationRegistry();
    final builder = EvidenceBuilder(
      tokenizePort: _FakeTokenize(<Token>[_token('何卒', 0), _token('宜しく', 2)]),
      lookupPort: _FakeLookup(),
      grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
      citations: citations,
      maxTargets: 1,
    );

    final bundle = await builder.build(
      sources: <AgentSourceInput>[_source('何卒宜しく')],
      dictionaries: const <DictionaryInfo>[_dictionaryA],
    );

    expect(bundle.truncated, isTrue);
    expect(bundle.budget.uniqueTargets, 1);
    expect(bundle.sources.single.tokens.last.citationIds, isEmpty);
  });

  test('a failing dictionary is recorded instead of silently swallowed', () async {
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
  });

  test('a missing UniDic degrades instead of failing the run', () async {
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
    expect(bundle.citations, isEmpty);
  });
}
