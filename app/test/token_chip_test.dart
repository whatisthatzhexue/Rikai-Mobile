import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/annotation_rules.dart';
import 'package:lexicandy/core/models/token.dart';
import 'package:lexicandy/core/theme/app_tokens.dart';
import 'package:lexicandy/core/ui/pitch_accent_overlay.dart';
import 'package:lexicandy/features/reader/reader_block.dart';
import 'package:lexicandy/features/reader/token_chip.dart';

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

Token _pitchToken({
  required String surface,
  required String lemma,
  required String kana,
  required String pos1,
  String cForm = '*',
  String accentType = '0',
}) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = pos1;
  features[5] = cForm;
  features[7] = lemma;
  features[20] = kana;
  features[24] = accentType;
  return Token.fromFeatures(
    surface: surface,
    features: features,
    start: 0,
    end: surface.length,
  );
}

Future<void> _pumpTokens(WidgetTester tester, List<Token> tokens) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ReaderBlock(
          tokens: tokens,
          fontSize: 20,
          showFurigana: true,
          annotationRules: AnnotationRuleSets.pitch,
        ),
      ),
    ),
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

  testWidgets('furigana covers only the unknown kanji stem', (tester) async {
    await _pumpToken(
      tester,
      _token(surface: '悩んでも', kana: 'ナヤンデモ', pos1: '動詞'),
    );

    expect(find.text('悩'), findsOneWidget);
    expect(find.text('なや'), findsOneWidget);
    expect(find.text('んでも'), findsOneWidget);
    expect(find.text('悩んでも'), findsNothing);
    expect(find.text('なやんでも'), findsNothing);
  });

  testWidgets('annotation rule sets control ruby and pitch', (tester) async {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '名詞';
    features[20] = 'トウキョウ';
    features[24] = '0';
    final token = Token.fromFeatures(
      surface: '東京',
      features: features,
      start: 0,
      end: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TokenChip(
            token: token,
            fontSize: 20,
            showFurigana: true,
            annotationRules: AnnotationRuleSets.basic,
          ),
        ),
      ),
    );
    expect(find.text('とうきょう'), findsOneWidget);
    expect(find.byType(PitchAccentOverlay), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TokenChip(
            token: token,
            fontSize: 20,
            showFurigana: true,
            annotationRules: AnnotationRuleSets.pitch,
          ),
        ),
      ),
    );
    expect(find.text('とうきょう'), findsOneWidget);
    expect(find.byType(PitchAccentOverlay), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TokenChip(
            token: token,
            fontSize: 20,
            showFurigana: true,
            annotationRules: AnnotationRuleSets.none,
          ),
        ),
      ),
    );
    expect(find.text('とうきょう'), findsNothing);
    expect(find.byType(PitchAccentOverlay), findsNothing);
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

  testWidgets('inflected verbs drop pitch before another token', (
    tester,
  ) async {
    await _pumpTokens(tester, <Token>[
      _pitchToken(
        surface: '食べ',
        lemma: '食べる',
        kana: 'タベ',
        pos1: '動詞',
        cForm: '連用形-一般',
      ),
      _pitchToken(
        surface: 'ます',
        lemma: 'ます',
        kana: 'マス',
        pos1: '助動詞',
        accentType: '*',
      ),
    ]);
    expect(find.byType(PitchAccentOverlay), findsNothing);

    await _pumpTokens(tester, <Token>[
      _pitchToken(
        surface: '食べ',
        lemma: '食べる',
        kana: 'タベ',
        pos1: '動詞',
        cForm: '連用形-一般',
      ),
      _pitchToken(
        surface: '。',
        lemma: '。',
        kana: '。',
        pos1: '補助記号',
        accentType: '*',
      ),
    ]);
    expect(find.byType(PitchAccentOverlay), findsWidgets);
  });

  testWidgets('onbin verbs keep pitch and inflected adjectives drop it', (
    tester,
  ) async {
    await _pumpTokens(tester, <Token>[
      _pitchToken(
        surface: '書い',
        lemma: '書く',
        kana: 'カイ',
        pos1: '動詞',
        cForm: '連用形-イ音便',
      ),
      _pitchToken(
        surface: 'た',
        lemma: 'た',
        kana: 'タ',
        pos1: '助動詞',
        accentType: '*',
      ),
    ]);
    expect(find.byType(PitchAccentOverlay), findsWidgets);

    await _pumpTokens(tester, <Token>[
      _pitchToken(
        surface: '美しく',
        lemma: '美しい',
        kana: 'ウツクシク',
        pos1: '形容詞',
        cForm: '連用形-一般',
      ),
      _pitchToken(
        surface: 'て',
        lemma: 'て',
        kana: 'テ',
        pos1: '助詞',
        accentType: '*',
      ),
    ]);
    expect(find.byType(PitchAccentOverlay), findsNothing);

    await _pumpTokens(tester, <Token>[
      _pitchToken(
        surface: '美しい',
        lemma: '美しい',
        kana: 'ウツクシイ',
        pos1: '形容詞',
        cForm: '終止形-一般',
      ),
      _pitchToken(
        surface: '。',
        lemma: '。',
        kana: '。',
        pos1: '補助記号',
        accentType: '*',
      ),
    ]);
    expect(find.byType(PitchAccentOverlay), findsWidgets);
  });
}
