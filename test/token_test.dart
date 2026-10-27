import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/token.dart';

List<String> _features({
  String pos1 = '名詞',
  String pos2 = '普通名詞',
  String pos3 = '一般',
  String pos4 = '*',
  String cType = '*',
  String cForm = '*',
  String lForm = 'トウキョウ',
  String lemma = '東京',
  String orth = '東京',
  String pron = 'トーキョー',
  String orthBase = '東京',
  String pronBase = 'トーキョー',
  String goshu = '漢',
  String kana = 'トウキョウ',
  String kanaBase = 'トウキョウ',
  String lid = '12345',
  String lemmaId = '67890',
}) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = pos1;
  features[1] = pos2;
  features[2] = pos3;
  features[3] = pos4;
  features[4] = cType;
  features[5] = cForm;
  features[6] = lForm;
  features[7] = lemma;
  features[8] = orth;
  features[9] = pron;
  features[10] = orthBase;
  features[11] = pronBase;
  features[12] = goshu;
  features[20] = kana;
  features[21] = kanaBase;
  features[27] = lid;
  features[28] = lemmaId;
  return features;
}

Token _token({
  String surface = '東京',
  List<String>? features,
  int start = 0,
  int end = 2,
}) {
  return Token.fromFeatures(
    surface: surface,
    features: features ?? _features(),
    start: start,
    end: end,
  );
}

void main() {
  group('field mapping', () {
    test('maps the 29-field UniDic layout', () {
      final token = _token(start: 3, end: 5);

      expect(token.pos1, '名詞');
      expect(token.pos2, '普通名詞');
      expect(token.pos3, '一般');
      expect(token.pos4, '*');
      expect(token.cType, '*');
      expect(token.cForm, '*');
      expect(token.lForm, 'トウキョウ');
      expect(token.lemma, '東京');
      expect(token.orth, '東京');
      expect(token.pron, 'トーキョー');
      expect(token.orthBase, '東京');
      expect(token.pronBase, 'トーキョー');
      expect(token.goshu, '漢');
      expect(token.kana, 'トウキョウ');
      expect(token.kanaBase, 'トウキョウ');
      expect(token.lid, '12345');
      expect(token.lemmaId, '67890');
      expect(token.start, 3);
      expect(token.end, 5);
      expect(token.hasStandardLayout, isTrue);
    });

    test('degrades safely when the layout is not 29 fields', () {
      final token = _token(features: _features().sublist(0, 10));

      expect(token.hasStandardLayout, isFalse);
      expect(token.reading, '');
      expect(token.hasDistinctReading, isFalse);
      expect(token.pos1, '名詞');
      expect(token.surface, '東京');
    });
  });

  group('reading', () {
    test('prefers kana and converts katakana to hiragana', () {
      expect(_token().reading, 'とうきょう');
    });

    test('falls back to pron when kana is empty', () {
      final token = _token(
        features: _features(kana: '', pron: 'トーキョー'),
      );
      expect(token.reading, 'とーきょー');
    });

    test('falls back to lForm when kana and pron are empty', () {
      final token = _token(
        features: _features(kana: '', pron: '', lForm: 'トウキョウ'),
      );
      expect(token.reading, 'とうきょう');
    });

    test('falls back to the surface form', () {
      final token = _token(
        surface: '東京',
        features: _features(kana: '', pron: '', lForm: ''),
      );
      expect(token.reading, '東京');
      expect(token.hasDistinctReading, isFalse);
    });

    test('hiragana surface has no distinct reading', () {
      final token = _token(
        surface: 'た',
        end: 1,
        features: _features(
          pos1: '助動詞',
          kana: 'タ',
          pron: 'タ',
          lForm: 'タ',
          lemma: 'た',
        ),
      );
      expect(token.reading, 'た');
      expect(token.hasDistinctReading, isFalse);
    });
  });

  group('classification', () {
    test('content words are highlighted', () {
      expect(_token().isContentWord, isTrue);
      expect(_token().isPunctuationOrSymbol, isFalse);
    });

    test('particles are not content words', () {
      final token = _token(
        surface: 'は',
        end: 1,
        features: _features(pos1: '助詞', pos2: '係助詞'),
      );
      expect(token.isContentWord, isFalse);
      expect(token.isPunctuationOrSymbol, isFalse);
    });

    test('punctuation is neither clickable nor annotated', () {
      final token = _token(
        surface: '、',
        end: 1,
        features: _features(pos1: '補助記号', pos2: '読点'),
      );
      expect(token.isPunctuationOrSymbol, isTrue);
      expect(token.isContentWord, isFalse);
    });

    test('shape words are content words', () {
      final token = _token(features: _features(pos1: '形状詞'));
      expect(token.isContentWord, isTrue);
    });
  });

  group('lookup candidates', () {
    test('orders candidates and removes duplicates', () {
      final token = _token(
        surface: '食べた',
        features: _features(
          orthBase: '食べる',
          lemma: '食べる',
          orth: '食べ',
          kanaBase: 'タベル',
          kana: 'タベ',
          pron: 'タベ',
        ),
      );

      expect(token.lookupCandidates, ['食べる', '食べ', 'タベル', 'タベ', '食べた']);
    });

    test('falls back to the surface when all fields are empty', () {
      final features = List<String>.filled(Token.expectedFeatureCount, '');
      final token = _token(surface: '未知', features: features);

      expect(token.lookupCandidates, ['未知']);
    });
  });
}
