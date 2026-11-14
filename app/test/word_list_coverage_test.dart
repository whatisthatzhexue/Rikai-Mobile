import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/models/lookup_match_mode.dart';
import 'package:lexicandy/core/models/lookup_models.dart';
import 'package:lexicandy/core/models/lookup_request.dart';
import 'package:lexicandy/services/agent/familiarization/built_in_word_lists.dart';
import 'package:lexicandy/services/agent/familiarization/word_list_coverage.dart';
import 'package:lexicandy/services/agent/ports/lookup_port.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

class _FakeLookup implements LookupPort {
  _FakeLookup({
    this.exactHits = const <String>{},
    this.prefixHits = const <String>{},
  });

  final Set<String> exactHits;
  final Set<String> prefixHits;
  final List<String> calls = <String>[];

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    calls.add('${request.matchMode.name}:${request.query}');
    final hit = request.matchMode == LookupMatchMode.exact
        ? exactHits.contains(request.query)
        : request.matchMode == LookupMatchMode.prefix &&
              prefixHits.contains(request.query);
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: hit
              ? <LookupEntry>[
                  LookupEntry(
                    matchedKey: request.query,
                    headword: request.query,
                    html: 'hit',
                  ),
                ]
              : const <LookupEntry>[],
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('word list coverage counts exact/prefix hits by tag', () async {
    final packs = builtInWordListPacks;
    final pack = packs.firstWhere((item) => item.language == 'ja');
    final lookup = _FakeLookup(
      exactHits: <String>{pack.entries[0].term, pack.entries[1].term},
      prefixHits: <String>{pack.entries[2].term},
    );

    final coverage = await evaluateWordListCoverage(
      pack: pack,
      dictionary: _dictionary,
      lookupPort: lookup,
    );

    expect(coverage.total, 21);
    expect(coverage.hits, 3);
    expect(coverage.hitRate, closeTo(3 / 21, 1e-9));
    expect(coverage.hitsByTag['greeting'], 3);
    expect(coverage.hitsByTag['family'], 0);
    expect(
      lookup.calls,
      containsAll(<String>[
        'exact:${pack.entries[2].term}',
        'prefix:${pack.entries[2].term}',
      ]),
    );
  });

  test('coverage reports zero when every lookup misses', () async {
    final packs = builtInWordListPacks;
    final pack = packs.firstWhere((item) => item.language == 'zh');

    final coverage = await evaluateWordListCoverage(
      pack: pack,
      dictionary: _dictionary,
      lookupPort: _FakeLookup(),
    );

    expect(coverage.hits, 0);
    expect(coverage.hitRate, 0);
    expect(coverage.hitsByTag.values, everyElement(0));
  });
}
