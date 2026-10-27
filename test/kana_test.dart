import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/utils/kana.dart';

void main() {
  group('katakanaToHiragana', () {
    test('converts common katakana', () {
      expect(katakanaToHiragana('タベル'), 'たべる');
      expect(katakanaToHiragana('トウキョウ'), 'とうきょう');
      expect(katakanaToHiragana('ヴァイオリン'), 'ゔぁいおりん');
    });

    test('keeps prolonged sound marks and punctuation', () {
      expect(katakanaToHiragana('コーヒー'), 'こーひー');
      expect(katakanaToHiragana('・'), '・');
    });

    test('maps rare katakana and iteration marks', () {
      expect(katakanaToHiragana('ヷヸヹヺ'), 'わゐゑを');
      expect(katakanaToHiragana('ヽヾ'), 'ゝゞ');
    });

    test('leaves non-katakana unchanged', () {
      expect(katakanaToHiragana('ABC東京123'), 'ABC東京123');
    });
  });

  group('hiraganaToKatakana', () {
    test('converts hiragana', () {
      expect(hiraganaToKatakana('たべる'), 'タベル');
      expect(hiraganaToKatakana('とうきょう'), 'トウキョウ');
    });

    test('keeps prolonged sound marks', () {
      expect(hiraganaToKatakana('こーひー'), 'コーヒー');
    });
  });

  test('containsKana', () {
    expect(containsKana('東京'), isFalse);
    expect(containsKana('とうきょう'), isTrue);
    expect(containsKana('トウキョウ'), isTrue);
  });
}
