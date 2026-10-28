import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/reader/token_chip.dart';

Token _token({
  required String surface,
  required String kana,
  required String pos1,
}) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = pos1;
  features[20] = kana;
  return Token.fromFeatures(
    surface: surface,
    features: features,
    start: 0,
    end: surface.length,
  );
}

Future<void> _pumpToken(WidgetTester tester, Token token) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: TokenChip(token: token, fontSize: 20, showFurigana: true),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('content words use brand blue and blue furigana', (tester) async {
    await _pumpToken(tester, _token(surface: '東京', kana: 'トウキョウ', pos1: '名詞'));

    final surface = tester.widget<Text>(find.text('東京'));
    final furigana = tester.widget<Text>(find.text('とうきょう'));
    expect(surface.style?.color, AppColors.onPrimaryContainer);
    expect(furigana.style?.color, AppColors.primary);
  });

  testWidgets('function words and punctuation use black, not grey', (
    tester,
  ) async {
    await _pumpToken(tester, _token(surface: 'た', kana: 'タ', pos1: '助動詞'));

    final auxiliary = tester.widget<Text>(find.text('た'));
    expect(auxiliary.style?.color, AppColors.textPrimary);
    expect(auxiliary.style?.color, isNot(AppColors.textSecondary));

    await _pumpToken(tester, _token(surface: '。', kana: '。', pos1: '補助記号'));

    final punctuation = tester.widget<Text>(find.text('。'));
    expect(punctuation.style?.color, AppColors.textPrimary);
  });
}
