import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_match_mode.dart';
import 'package:rikai_mobile/features/lookup/lookup_actions.dart';

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
}
