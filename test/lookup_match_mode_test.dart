import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/lookup_match_mode.dart';

void main() {
  test('labels cover all four lookup modes', () {
    expect(LookupMatchMode.values.map((mode) => mode.label), [
      '增量搜索',
      '完全匹配',
      '前方匹配',
      '后方匹配',
    ]);
  });

  test('matches exact/prefix/suffix/incremental keys', () {
    const key = 'ありがとう';
    expect(keyMatchesLookupMode(key, 'ありがとう', LookupMatchMode.exact), isTrue);
    expect(keyMatchesLookupMode(key, 'ありがとう', LookupMatchMode.prefix), isTrue);
    expect(keyMatchesLookupMode(key, 'ありがとう', LookupMatchMode.suffix), isTrue);
    expect(
      keyMatchesLookupMode(key, 'ありがとう', LookupMatchMode.incremental),
      isTrue,
    );
    expect(keyMatchesLookupMode(key, 'ありが', LookupMatchMode.prefix), isTrue);
    expect(keyMatchesLookupMode(key, 'ありが', LookupMatchMode.suffix), isFalse);
    expect(keyMatchesLookupMode(key, 'がとう', LookupMatchMode.suffix), isTrue);
    expect(
      keyMatchesLookupMode(key, 'がと', LookupMatchMode.incremental),
      isTrue,
    );
  });
}
