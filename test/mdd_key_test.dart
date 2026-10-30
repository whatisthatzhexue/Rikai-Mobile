import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/mdict/mdd_key.dart';

void main() {
  test('adds a leading backslash for root MDD keys', () {
    final candidates = mddKeyCandidates('3913.png');

    expect(candidates, contains(r'\3913.png'));
    expect(candidates, contains('3913.png'));
  });

  test('normalizes slash separators to backslashes', () {
    final candidates = mddKeyCandidates('JC_Z24Z/A471.png');

    expect(candidates, contains(r'\JC_Z24Z\A471.png'));
    expect(candidates, contains('JC_Z24Z/A471.png'));
  });

  test('strips file:// prefixes and leading separators', () {
    final candidates = mddKeyCandidates('file:///JC_Z24Z/A471.png');

    expect(candidates, contains(r'\JC_Z24Z\A471.png'));
  });

  test('strips sound:// prefixes used by MDD audio', () {
    final candidates = mddKeyCandidates('sound://audio/word.mp3');

    expect(candidates, contains(r'\audio\word.mp3'));
    expect(candidates, contains('audio/word.mp3'));
  });

  test('strips relative parent prefixes from nested CSS/HTML', () {
    final candidates = mddKeyCandidates('../gaiji/参照.svg');

    expect(candidates, contains(r'\gaiji\参照.svg'));
  });

  test('decodes percent-encoded keys', () {
    final candidates = mddKeyCandidates('%5CJC_Z24Z%5CA471.png');

    expect(candidates, contains(r'\JC_Z24Z\A471.png'));
  });

  test('returns no candidates for an empty value', () {
    expect(mddKeyCandidates(''), isEmpty);
    expect(mddKeyCandidates('   '), isEmpty);
  });
}
