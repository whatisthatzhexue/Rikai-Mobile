import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/utils/dictionary_entry_title.dart';

void main() {
  test('extracts the Japanese headword from bracketed entry content', () {
    expect(
      extractDictionaryEntryTitle('<div>く・べる[2] [0]【焼▽べる】（動バ下一）燃やす。</div>'),
      '焼べる',
    );
    expect(extractDictionaryEntryTitle('<div>今いま【今】［名］現在の時点。</div>'), '今');
    expect(extractDictionaryEntryTitle('<div>それ[0]【其▼れ】（代）あれ。</div>'), '其れ');
    expect(
      extractDictionaryEntryTitle('<div>のろいのろひ【呪い・詛▼い】のろうこと。</div>'),
      '呪い・詛い',
    );
  });

  test('uses the first line simplest word without a bracket convention', () {
    expect(extractDictionaryEntryTitle('<div>りんご 果物の一種。</div>'), 'りんご');
    expect(extractDictionaryEntryTitle('<div>苹果 一种水果。</div>'), '苹果');
    expect(
      extractDictionaryEntryTitle('<div>apple a fruit for eating.</div>'),
      'apple',
    );
  });

  test('prefers a kanji bracket title over a kana headword class', () {
    expect(
      extractDictionaryEntryTitle(
        '<div><span class="headword">く・べる</span>'
        '<span class="definition">【焼▽べる】燃やす。</span></div>',
      ),
      '焼べる',
    );
  });

  test('uses a title element when the entry has no bracket title', () {
    expect(
      extractDictionaryEntryTitle(
        '<div><h1 class="entry-title">愛</h1><p>あい。</p></div>',
      ),
      '愛',
    );
    expect(
      extractDictionaryEntryTitle('<h2>apple</h2><p>a fruit.</p>'),
      'apple',
    );
  });

  test('ignores bracket labels such as 使い方 and 類語', () {
    expect(extractDictionaryEntryTitle('<div>【使い方】【類語】今いま【今】</div>'), '今');
  });

  test('detects internal ids but not real headwords', () {
    expect(isOpaqueDictionaryKey('01570 03798'), isTrue);
    expect(isOpaqueDictionaryKey('00044'), isTrue);
    expect(isOpaqueDictionaryKey('@daijirin2-044903-0000'), isTrue);
    expect(isOpaqueDictionaryKey('daijirin2-044903-0000'), isTrue);
    expect(isOpaqueDictionaryKey('何卒'), isFalse);
    expect(isOpaqueDictionaryKey('apple'), isFalse);
    expect(isOpaqueDictionaryKey('B2B'), isFalse);
  });

  test('falls back to the matched key and rejects opaque keys', () {
    expect(
      dictionaryEntryDisplayTitle(
        html: '<div></div>',
        matchedKey: '愛',
        headword: '00044',
      ),
      '愛',
    );
    expect(
      dictionaryEntryDisplayTitle(
        html: '<div></div>',
        matchedKey: '01570 03798',
        headword: '01570 03798',
      ),
      '',
    );
  });

  test('extracts a title from a saved citation snippet', () {
    expect(
      extractDictionaryEntryTitleFromText('［使い方］［品格］今か今かと今となっては今いま【今】［名］現在。'),
      '今',
    );
    expect(extractDictionaryEntryTitleFromText('く・べる[2] [0]【焼▽べる】燃やす。'), '焼べる');
    expect(extractDictionaryEntryTitleFromText('definition only'), isNull);
  });
}
