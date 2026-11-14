import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/word_list_pack.dart';
import 'package:rikai_mobile/services/agent/familiarization/built_in_word_lists.dart';

void main() {
  test('built-in word list packs are static, valid and tagged', () {
    final packs = builtInWordListPacks;
    expect(packs, hasLength(3));
    expect(
      packs.map((pack) => pack.language),
      containsAll(<String>['ja', 'zh', 'en']),
    );
    for (final pack in packs) {
      expect(pack.isValid, isTrue, reason: pack.id);
      expect(pack.entries, hasLength(wordListTotalEntries));
      expect(pack.countsByTag, wordListTagCounts);
    }
  });

  test('word-list tags stay semantic, not part-of-speech', () {
    expect(
      wordListTagIds,
      unorderedEquals(<String>[
        'greeting',
        'family',
        'food',
        'person_name',
        'place_name',
      ]),
    );
    expect(
      wordListTagIds.where(
        const <String>{'verb', 'adjective', 'particle', 'auxiliary'}.contains,
      ),
      isEmpty,
    );
  });

  test('validation rejects wrong counts, duplicates and unknown tags', () {
    final source = WordListPack.fromJson(<String, Object?>{
      'id': 'test',
      'language': 'ja',
      'version': 1,
      'entries': <Map<String, Object?>>[
        for (var index = 0; index < 21; index++)
          <String, Object?>{
            'term': index == 0 || index == 20 ? 'こんにちは' : '語$index',
            'tag': index < 5
                ? 'greeting'
                : index < 10
                ? 'family'
                : index < 15
                ? 'food'
                : index < 18
                ? 'person_name'
                : 'place_name',
          },
      ],
    });
    final errors = source.validate();
    expect(errors, contains('词表包含重复词条 こんにちは'));

    final short = WordListPack.fromJson(<String, Object?>{
      'id': 'short',
      'language': 'ja',
      'entries': <Map<String, Object?>>[
        <String, Object?>{'term': 'こんにちは', 'tag': 'greeting'},
      ],
    });
    expect(short.validate(), contains('词表必须正好 21 项，实际 1'));

    final unknownTag = WordListPack.fromJson(<String, Object?>{
      'id': 'bad-tag',
      'language': 'ja',
      'entries': <Map<String, Object?>>[
        <String, Object?>{'term': 'こんにちは', 'tag': 'unknown'},
      ],
    });
    expect(unknownTag.validate(), contains('词表包含未知标签 unknown'));
  });
}
