import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_match_mode.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/services/lookup/lookup_gateway.dart';

class _FakeBackend implements LookupBackend {
  List<DictionaryInfo>? dictionaries;
  Iterable<String>? candidates;
  LookupMatchMode? matchMode;
  int? maxEntries;

  @override
  Future<LookupResult> lookup({
    required String query,
    required Iterable<String> rawCandidates,
    required List<DictionaryInfo> dictionaries,
    LookupMatchMode matchMode = LookupMatchMode.exact,
    int maxEntriesPerDictionary = 0,
    int suggestionLimit = 30,
  }) async {
    this.dictionaries = dictionaries;
    candidates = rawCandidates;
    this.matchMode = matchMode;
    maxEntries = maxEntriesPerDictionary;
    return LookupResult(
      query: query,
      candidates: rawCandidates.toList(growable: false),
      groups: const <DictionaryLookupGroup>[],
    );
  }
}

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

void main() {
  test('rejects an empty or unavailable dictionary selection', () async {
    final gateway = LookupGateway(_FakeBackend());
    expect(
      () => gateway.lookup(
        const LookupRequest(query: '東京', dictionaries: <DictionaryInfo>[]),
      ),
      throwsA(isA<LookupGatewayException>()),
    );

    final disabled = _dictionaryA.copyWith(enabled: false);
    expect(
      () => gateway.lookup(
        LookupRequest(query: '東京', dictionaries: <DictionaryInfo>[disabled]),
      ),
      throwsA(isA<LookupGatewayException>()),
    );
  });

  test(
    'preserves dictionary order and defaults candidates to the query',
    () async {
      final backend = _FakeBackend();
      final gateway = LookupGateway(backend);

      await gateway.lookup(
        const LookupRequest(
          query: '東京',
          dictionaries: <DictionaryInfo>[_dictionaryB, _dictionaryA],
          matchMode: LookupMatchMode.prefix,
          maxEntriesPerDictionary: 4,
        ),
      );

      expect(backend.dictionaries!.map((item) => item.id), ['b', 'a']);
      expect(backend.candidates, ['東京']);
      expect(backend.matchMode, LookupMatchMode.prefix);
      expect(backend.maxEntries, 4);
    },
  );
}
