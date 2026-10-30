import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';

Token _token(String surface, int start, {String lemma = ''}) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = '動詞';
  features[7] = lemma.isEmpty ? surface : lemma;
  features[8] = surface;
  return Token.fromFeatures(
    surface: surface,
    features: features,
    start: start,
    end: start + surface.length,
  );
}

void main() {
  test('matches the longest non-overlapping pattern first', () {
    final catalog = GrammarPatternCatalog.fromJson(<String, Object?>{
      'patterns': <Object?>[
        <String, Object?>{
          'id': 'te-shima',
          'surface': 'てしま',
          'token_pattern': <String>['て', 'しま'],
        },
        <String, Object?>{
          'id': 'te-shimatta',
          'surface': 'てしまった',
          'token_pattern': <String>['て', 'しま', 'った'],
        },
      ],
    });
    final tokens = <Token>[
      _token('食べ', 0),
      _token('て', 2),
      _token('しま', 3),
      _token('った', 5),
    ];

    final matches = catalog.match(tokens);
    expect(matches, hasLength(1));
    expect(matches.single.pattern.id, 'te-shimatta');
    expect(matches.single.startTokenIndex, 1);
    expect(matches.single.endTokenIndex, 4);
    expect(matches.single.start, 2);
    expect(matches.single.end, 7);
  });

  test('falls back to lemma when the surface is inflected', () {
    final catalog = GrammarPatternCatalog.fromJson(<String, Object?>{
      'patterns': <Object?>[
        <String, Object?>{
          'id': 'to-omou',
          'surface': 'と思う',
          'token_pattern': <String>['と', '思う'],
        },
      ],
    });
    final tokens = <Token>[_token('と', 0), _token('思い', 1, lemma: '思う')];

    final matches = catalog.match(tokens);
    expect(matches, hasLength(1));
    expect(matches.single.pattern.id, 'to-omou');
  });
}
