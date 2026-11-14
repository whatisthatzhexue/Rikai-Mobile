import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_input.dart';
import 'package:lexicandy/core/models/agent/agent_limits.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/models/lookup_models.dart';
import 'package:lexicandy/core/models/lookup_request.dart';
import 'package:lexicandy/core/models/token.dart';
import 'package:lexicandy/services/agent/citation_registry.dart';
import 'package:lexicandy/services/agent/evidence_builder.dart';
import 'package:lexicandy/services/agent/grammar_patterns.dart';
import 'package:lexicandy/services/agent/ports/lookup_port.dart';
import 'package:lexicandy/services/agent/ports/tokenize_port.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

class _NeverTokenize implements TokenizePort {
  int calls = 0;

  @override
  Future<List<Token>> analyze(String text) async {
    calls++;
    throw StateError('non-Japanese text must not reach UniDic');
  }
}

class _EmptyLookup implements LookupPort {
  int calls = 0;

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    calls++;
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: const <DictionaryLookupGroup>[],
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
  test(
    'non-Japanese source skips UniDic but keeps raw lookup targets',
    () async {
      final tokenizer = _NeverTokenize();
      final lookup = _EmptyLookup();
      final builder = EvidenceBuilder(
        tokenizePort: tokenizer,
        lookupPort: lookup,
        grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
        citations: CitationRegistry(),
        limits: const AgentLimits(maxTargets: 10, maxEvidenceEntries: 5),
      );

      final evidence = await builder.build(
        sources: const <AgentSourceInput>[
          AgentSourceInput(
            id: 'src-1',
            kind: AgentSourceKind.userText,
            text: 'hello world',
          ),
        ],
        dictionaries: const <DictionaryInfo>[_dictionary],
      );

      expect(tokenizer.calls, 0);
      expect(evidence.structureUnavailable, isTrue);
      expect(evidence.sources.single.tokens, isEmpty);
      expect(evidence.budget.uniqueTargets, greaterThan(0));
      expect(lookup.calls, greaterThan(0));
    },
  );
}
