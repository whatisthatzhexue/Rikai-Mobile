import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/utils/script_language.dart';

void main() {
  test('detects Japanese, Latin and non-Japanese scripts', () {
    expect(detectScriptLanguage('何卒宜しく'), ScriptLanguage.japanese);
    expect(detectScriptLanguage('hello world'), ScriptLanguage.latin);
    expect(detectScriptLanguage('안녕하세요'), ScriptLanguage.korean);
    expect(detectScriptLanguage('привет'), ScriptLanguage.cyrillic);
    expect(detectScriptLanguage('สวัสดี'), ScriptLanguage.thai);
    expect(detectScriptLanguage('مرحبا'), ScriptLanguage.arabic);
    expect(detectScriptLanguage('γειά'), ScriptLanguage.greek);
  });

  test('Han-only text remains ambiguous and keeps the Japanese tokenizer', () {
    expect(detectScriptLanguage('何卒'), isNull);
    expect(shouldUseJapaneseTokenizer('何卒'), isTrue);
    expect(shouldUseJapaneseTokenizer('hello world'), isFalse);
    expect(shouldUseJapaneseTokenizer('何卒宜しく'), isTrue);
  });
}
