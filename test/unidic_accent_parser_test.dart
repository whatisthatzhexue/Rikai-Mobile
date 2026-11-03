import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_pitch.dart';
import 'package:rikai_mobile/services/mecab/unidic_accent_parser.dart';

void main() {
  group('real UniDic accent samples', () {
    final cases = <(String, String, int, String)>[
      ('橋', 'はし', 2, 'LH'),
      ('箸', 'はし', 1, 'HL'),
      ('端', 'はし', 0, 'LH'),
      ('東京', 'とうきょう', 0, 'LHHH'),
      ('日本', 'にっぽん', 3, 'LHHL'),
      ('食べる', 'たべる', 2, 'LHL'),
      ('花', 'はな', 2, 'LH'),
      ('雨', 'あめ', 1, 'HL'),
      ('飴', 'あめ', 0, 'LH'),
      ('今日', 'きょう', 1, 'HL'),
    ];

    for (final (surface, reading, type, pattern) in cases) {
      test('$surface -> $pattern', () {
        final accent = parseUnidicAccent(accentType: '$type', reading: reading);
        expect(accent, isNotNull);
        expect(accent!.accentType, type);
        expect(accent.moraCount, pattern.length);
        expect(accent.moraPattern, pattern);
        expect(accent.isValid, isTrue);
        expect(AgentPitchAccent.source, 'unidic');
      });
    }
  });

  test('splits small kana, っ, ん and long vowels as one mora', () {
    expect(splitJapaneseMorae('きょう'), <String>['きょ', 'う']);
    expect(splitJapaneseMorae('とうきょう'), <String>['と', 'う', 'きょ', 'う']);
    expect(splitJapaneseMorae('にっぽん'), <String>['に', 'っ', 'ぽ', 'ん']);
    expect(splitJapaneseMorae('コーヒー'), <String>['こ', 'ー', 'ひ', 'ー']);
  });

  test('katakana readings are normalized for mora counting', () {
    final accent = parseUnidicAccent(accentType: '2', reading: 'ハシ');
    expect(accent?.moraCount, 2);
    expect(accent?.moraPattern, 'LH');
  });

  test('missing or out-of-range accent data yields null', () {
    expect(parseUnidicAccent(accentType: '*', reading: 'はし'), isNull);
    expect(parseUnidicAccent(accentType: '', reading: 'はし'), isNull);
    expect(parseUnidicAccent(accentType: 'abc', reading: 'はし'), isNull);
    expect(parseUnidicAccent(accentType: '-1', reading: 'はし'), isNull);
    expect(parseUnidicAccent(accentType: '3', reading: 'はし'), isNull);
    expect(parseUnidicAccent(accentType: '1', reading: ''), isNull);
    expect(parseUnidicAccent(accentType: '1', reading: 'は'), isNull);
  });

  test('AgentPitchAccent JSON round-trips and validates', () {
    const accent = AgentPitchAccent(
      accentType: 2,
      moraCount: 3,
      moraPattern: 'LHL',
    );
    final restored = AgentPitchAccent.fromJson(accent.toJson());
    expect(restored.accentType, 2);
    expect(restored.moraCount, 3);
    expect(restored.moraPattern, 'LHL');
    expect(restored.isValid, isTrue);

    const invalid = AgentPitchAccent(
      accentType: 5,
      moraCount: 2,
      moraPattern: 'LH',
    );
    expect(invalid.isValid, isFalse);
  });
}
