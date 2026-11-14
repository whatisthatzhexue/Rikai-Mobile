import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/models/lookup_match_mode.dart';
import 'package:lexicandy/features/lookup/lookup_actions.dart';

void main() {
  test('entry links stay in the current dictionary and use exact matching', () {
    const current = DictionaryInfo(
      id: 'current',
      title: '当前词典',
      mdxPath: '/current.mdx',
    );
    final request = entryLinkLookupRequest(word: '東京', dictionary: current);

    expect(request.query, '東京');
    expect(request.rawCandidates, <String>['東京']);
    expect(request.dictionaries, <DictionaryInfo>[current]);
    expect(request.matchMode, LookupMatchMode.exact);
    expect(request.maxEntriesPerDictionary, 1);
  });

  test('entry link misses show a current-dictionary bubble', () {
    expect(entryLinkMissMessage('東京'), '当前词典中没有「東京」');
    expect(entryLinkMissMessage('daijirin2-011462-0000'), '当前词典中没有对应的词条');
    expect(entryLinkMissMessage('apple'), '当前词典中没有「apple」');
    expect(entryLinkMissMessage(''), '当前词典中没有对应的词条');
  });
}
