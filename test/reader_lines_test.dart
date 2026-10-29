import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/features/reader/reader_lines.dart';

Token _token(String surface, int start, int end) {
  return Token.fromFeatures(
    surface: surface,
    features: List<String>.filled(Token.expectedFeatureCount, ''),
    start: start,
    end: end,
  );
}

void main() {
  test('groups tokens into source lines and keeps blank lines', () {
    final text = '食べた\n\n東京';
    final lines = buildReaderLines(text, [
      _token('食べ', 0, 2),
      _token('た', 2, 3),
      _token('東京', 5, 7),
    ]);

    expect(lines, hasLength(3));
    expect(lines[0].tokens.map((token) => token.surface), ['食べ', 'た']);
    expect(lines[1].tokens, isEmpty);
    expect(lines[2].tokens.single.surface, '東京');
  });

  test('ignores tokens outside the supplied text', () {
    final lines = buildReaderLines('東京', [_token('東京', 0, 2)]);

    expect(lines.single.tokens.single.surface, '東京');
  });
}
