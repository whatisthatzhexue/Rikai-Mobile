import '../utils/kana.dart';

/// One morphologically analysed token produced by MeCab + UniDic.
///
/// UniDic (現代書き言葉 UniDic) emits 29 comma-separated features. The indices
/// below follow 現代書き言葉 UniDic 2025.12 as verified against its `sys.dic`:
///
/// | index | field |
/// |-------|-------|
/// | 0-3   | pos1-pos4 |
/// | 4     | cType (活用型) |
/// | 5     | cForm (活用形) |
/// | 6     | lForm (語彙素読み) |
/// | 7     | lemma (語彙素) |
/// | 8     | orth (書字形出現形) |
/// | 9     | pron (発音形出現形) |
/// | 10    | orthBase (書字形基本形) |
/// | 11    | pronBase (発音形基本形) |
/// | 12    | goshu (語種) |
/// | 20    | kana (仮名形出現形) |
/// | 21    | kanaBase (仮名形基本形) |
/// | 27    | lid |
/// | 28    | lemmaId |
///
/// If a dictionary with a different layout is used, [hasStandardLayout] is
/// false and [reading] falls back to an empty string: tokens stay selectable
/// but show no furigana instead of displaying wrong readings.
class Token {
  Token({
    required this.surface,
    required this.features,
    required this.start,
    required this.end,
    required this.pos1,
    required this.pos2,
    required this.pos3,
    required this.pos4,
    required this.cType,
    required this.cForm,
    required this.lForm,
    required this.lemma,
    required this.orth,
    required this.orthBase,
    required this.pron,
    required this.pronBase,
    required this.kana,
    required this.kanaBase,
    required this.goshu,
    required this.lid,
    required this.lemmaId,
  });

  /// The number of features emitted by the supported UniDic layout.
  static const int expectedFeatureCount = 29;

  /// Part-of-speech classes rendered as content words (highlighted).
  ///
  /// UniDic uses 形状詞 where IPADIC-style dictionaries say 形容動詞.
  static const Set<String> contentPos1 = {
    '名詞',
    '動詞',
    '形容詞',
    '形状詞',
    '副詞',
    '連体詞',
    '接頭辞',
    '接尾辞',
    '感動詞',
  };

  /// Builds a token from MeCab's surface and feature list.
  factory Token.fromFeatures({
    required String surface,
    required List<String> features,
    required int start,
    required int end,
  }) {
    String at(int index) =>
        index >= 0 && index < features.length ? features[index] : '';

    return Token(
      surface: surface,
      features: List<String>.unmodifiable(features),
      start: start,
      end: end,
      pos1: at(0),
      pos2: at(1),
      pos3: at(2),
      pos4: at(3),
      cType: at(4),
      cForm: at(5),
      lForm: at(6),
      lemma: at(7),
      orth: at(8),
      orthBase: at(10),
      pron: at(9),
      pronBase: at(11),
      kana: at(20),
      kanaBase: at(21),
      goshu: at(12),
      lid: at(27),
      lemmaId: at(28),
    );
  }

  /// Surface form as it appears in the input text.
  final String surface;

  /// Raw comma-separated features as emitted by MeCab.
  final List<String> features;

  /// UTF-16 offset (inclusive) in the analysed text.
  final int start;

  /// UTF-16 offset (exclusive) in the analysed text.
  final int end;

  final String pos1;
  final String pos2;
  final String pos3;
  final String pos4;
  final String cType;
  final String cForm;
  final String lForm;
  final String lemma;
  final String orth;
  final String orthBase;
  final String pron;
  final String pronBase;
  final String kana;
  final String kanaBase;
  final String goshu;
  final String lid;
  final String lemmaId;

  /// Whether the feature list matches the supported 29-field UniDic layout.
  bool get hasStandardLayout => features.length == expectedFeatureCount;

  /// Furigana, converted to hiragana.
  ///
  /// Priority: kana (20) → pron (9) → lForm (6) → surface.
  String get reading {
    if (!hasStandardLayout) return '';
    final raw = kana.isNotEmpty
        ? kana
        : pron.isNotEmpty
        ? pron
        : lForm.isNotEmpty
        ? lForm
        : surface;
    return katakanaToHiragana(raw);
  }

  /// Whether a furigana line adds information (reading exists and differs
  /// from the surface form).
  bool get hasDistinctReading => reading.isNotEmpty && reading != surface;

  /// Content words are highlighted and visually separated in the reader.
  bool get isContentWord => contentPos1.contains(pos1);

  /// Punctuation, symbols and whitespace are not clickable targets and never
  /// show furigana.
  bool get isPunctuationOrSymbol =>
      surface.trim().isEmpty || pos1 == '補助記号' || pos1 == '記号' || pos1 == '空白';

  /// Human-readable POS chain, e.g. `名詞・普通名詞・一般`.
  String get posLabel {
    final parts = [
      pos1,
      pos2,
      pos3,
      pos4,
    ].where((part) => part.isNotEmpty && part != '*');
    return parts.join('・');
  }

  /// Dictionary lookup candidates, most specific first.
  ///
  /// Order: orthBase → lemma → orth → kanaBase → kana → pron → surface.
  List<String> get lookupCandidates {
    final seen = <String>{};
    final candidates = <String>[];
    for (final raw in [orthBase, lemma, orth, kanaBase, kana, pron, surface]) {
      final value = raw.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      candidates.add(value);
    }
    return candidates;
  }

  @override
  String toString() =>
      'Token($surface, reading=$reading, pos=$posLabel, $start..$end)';
}
