import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/lookup/lookup_sheet.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Token _token({
  required String surface,
  required String kana,
  String pos1 = '名詞',
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

Future<void> _pumpLookupSheet(WidgetTester tester, Token token) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: LookupSheet(token: token)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the lookup sheet has no redundant close button', (tester) async {
    await _pumpLookupSheet(tester, _token(surface: 'ありがとう', kana: 'アリガトウ'));

    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('the reading is hidden when it equals the surface', (
    tester,
  ) async {
    await _pumpLookupSheet(tester, _token(surface: 'ありがとう', kana: 'アリガトウ'));

    expect(find.text('ありがとう'), findsOneWidget);
  });

  testWidgets('a distinct reading is still shown in brand blue', (
    tester,
  ) async {
    await _pumpLookupSheet(tester, _token(surface: '東京', kana: 'トウキョウ'));

    expect(find.text('東京'), findsOneWidget);
    final reading = tester.widget<Text>(find.text('とうきょう'));
    expect(reading.style?.color, AppColors.primary);
  });

  testWidgets('the title row keeps the mode toggle and lookup menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpLookupSheet(tester, _token(surface: 'ありがとう', kana: 'アリガトウ'));

    expect(find.text('多选'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
