import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/utils/text_normalizer.dart';

void main() {
  test('NFKC normalizes full-width ASCII and half-width katakana', () {
    expect(normalizeLookupText('ＡＢＣ１２３'), 'ABC123');
    expect(normalizeLookupText('ｶﾞｯｺｳ'), 'ガッコウ');
  });

  test('stripLookupKey removes whitespace and punctuation', () {
    expect(stripLookupKey(' 東 京・とうきょう、ABC '), '東京とうきょうabc');
    expect(stripLookupKey('食べる。'), '食べる');
  });

  test('candidates preserve raw priority and add kana variants', () {
    final candidates = lookupCandidatesFor(['食べる', 'たべる']);

    expect(candidates.first, '食べる');
    expect(candidates, contains('たべる'));
    expect(candidates, contains('食ベル'));
    expect(candidates, contains('タベル'));
  });

  test('candidates include NFKC width variants', () {
    final candidates = lookupCandidatesFor(['ＡＢＣ']);

    expect(candidates, contains('ABC'));
    expect(candidates, contains('abc'));
  });

  test('candidates are de-duplicated', () {
    final candidates = lookupCandidatesFor(['東京', '東京']);

    expect(candidates.where((value) => value == '東京'), hasLength(1));
  });

  test('empty and whitespace candidates are ignored', () {
    expect(lookupCandidatesFor(['', '   ']), isEmpty);
  });
}
