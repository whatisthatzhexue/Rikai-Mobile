import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/core/models/corpus_entry.dart';
import 'package:rikai_mobile/services/storage/history_store.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHistoryStore extends HistoryStore {
  String? savedText;

  @override
  Future<CorpusEntry> saveText({
    required String text,
    required String engine,
    required String mode,
    required String orientation,
    String blocksJson = '[]',
  }) async {
    savedText = text;
    return CorpusEntry(
      id: 'text-1',
      createdAt: DateTime(2026, 10, 30),
      title: text,
      imagePath: '',
      text: text,
      engine: engine,
      mode: mode,
      orientation: orientation,
      blocksJson: blocksJson,
    );
  }
}

void main() {
  testWidgets('reader can save typed text to the corpus', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.app_onboarding_completed': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final store = _FakeHistoryStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          historyStoreProvider.overrideWithValue(store),
        ],
        child: const RikaiApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查句子'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '保存するテキスト');
    await tester.tap(find.text('分词'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('保存到语料'));
    await tester.pumpAndSettle();

    expect(store.savedText, '保存するテキスト');
    // Let the toast timer expire so the test binding has no pending timers.
    await tester.pump(const Duration(seconds: 3));
  });
}
