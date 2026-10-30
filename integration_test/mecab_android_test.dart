import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/services/mecab/mecab_service.dart';
import 'package:rikai_mobile/services/storage/permission_service.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On CI/emulator runs the app is installed right before the test starts, so
/// the host grants MANAGE_EXTERNAL_STORAGE asynchronously. Wait for the
/// dictionary to become readable instead of failing immediately.
Future<void> _waitForUnidic(String path) async {
  final sysDic = File('$path/sys.dic');
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    if (await sysDic.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final status = await const PermissionService().getStatus();
  fail(
    'UniDic is not readable at $path after 120s '
    '(sdk=${status.sdkInt}, allFilesAccess=${status.allFilesAccess}, '
    'legacyRead=${status.legacyRead})',
  );
}

/// Runs against a real, user-supplied UniDic on a device or emulator:
///
/// ```bash
/// flutter test integration_test/mecab_android_test.dart -d emulator-5554 \
///   --dart-define=RIKAI_UNIDIC_PATH=/sdcard/Download/unidic-cwj-202512
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const dictDir = String.fromEnvironment('RIKAI_UNIDIC_PATH');

  testWidgets('All Files Access channel reports the granted state', (
    tester,
  ) async {
    final status = await const PermissionService().getStatus();
    // ignore: avoid_print
    print(
      'Storage permission: sdk=${status.sdkInt} '
      'allFilesAccess=${status.allFilesAccess} '
      'legacyRead=${status.legacyRead}',
    );
    expect(status.sdkInt, greaterThan(0));
    if (status.sdkInt >= 30) {
      expect(status.allFilesAccess, isTrue);
    } else {
      expect(status.legacyRead, isTrue);
    }
  });

  testWidgets('real UniDic tokenizes 食べた東京 with readings', (tester) async {
    expect(
      dictDir,
      isNotEmpty,
      reason:
          'Pass --dart-define=RIKAI_UNIDIC_PATH=/sdcard/Download/unidic-cwj-202512',
    );

    await _waitForUnidic(dictDir);
    final supportDirectory = await getApplicationSupportDirectory();
    final openStarted = DateTime.now();
    final service = await MecabService.open(
      dictDir: dictDir,
      rcDirectory: supportDirectory.path,
    );
    final openElapsed = DateTime.now().difference(openStarted);
    addTearDown(service.dispose);
    // ignore: avoid_print
    print('MecabService.open: ${openElapsed.inMilliseconds} ms');

    final tokens = await service.analyze('食べた東京');
    // ignore: avoid_print
    print(
      tokens
          .map(
            (token) =>
                '${token.surface}\t${token.reading}\t${token.posLabel}\t'
                '${token.lemma}\t${token.start}..${token.end}',
          )
          .join('\n'),
    );

    for (final token in tokens.where((token) => !token.hasStandardLayout)) {
      // ignore: avoid_print
      print(
        'NONSTANDARD surface=${token.surface} '
        'fields=${token.features.length} pos1=${token.pos1} '
        'raw=${token.features.join('|')}',
      );
    }

    expect(
      tokens.map((token) => token.surface),
      containsAllInOrder(['食べ', 'た', '東京']),
    );

    expect(tokens.every((token) => token.hasStandardLayout), isTrue);

    final taberu = tokens.firstWhere((token) => token.surface == '食べ');
    expect(taberu.reading, 'たべ');
    expect(taberu.pos1, '動詞');

    // 助動詞 entries contain a quoted comma field
    // ("動詞%F2@1,形容詞%F4@-2"); the CSV-aware parser must keep 29 fields.
    final ta = tokens.firstWhere((token) => token.surface == 'た');
    expect(ta.features, hasLength(29));
    expect(ta.reading, 'た');
    expect(ta.lemma, 'た');
    expect(ta.lid, isNotEmpty);

    final tokyo = tokens.firstWhere((token) => token.surface == '東京');
    expect(tokyo.reading, 'とうきょう');
    expect(tokyo.pos1, '名詞');
    expect(tokyo.lookupCandidates, isNotEmpty);
    expect(tokyo.start, 3);
    expect(tokyo.end, 5);

    final multiline = await service.analyze('東京\n食べた');
    expect(
      multiline.map((token) => token.surface),
      containsAllInOrder(['東京', '食べ', 'た']),
    );
    final secondTokyo = multiline.firstWhere((token) => token.surface == '東京');
    expect(secondTokyo.start, 0);
    final secondTaberu = multiline.firstWhere((token) => token.surface == '食べ');
    expect(secondTaberu.start, 3);
  });

  testWidgets('tokenizes a longer sample within the Phase 1 budget', (
    tester,
  ) async {
    expect(dictDir, isNotEmpty);

    await _waitForUnidic(dictDir);
    final supportDirectory = await getApplicationSupportDirectory();
    final service = await MecabService.open(
      dictDir: dictDir,
      rcDirectory: supportDirectory.path,
    );
    addTearDown(service.dispose);

    final text = List.filled(100, '吾輩は猫である。名前はまだ無い。').join();
    final started = DateTime.now();
    final tokens = await service.analyze(text);
    final elapsed = DateTime.now().difference(started);

    final nonstandard = tokens
        .where((token) => !token.hasStandardLayout)
        .toList();
    // ignore: avoid_print
    print(
      'Analyzed ${tokens.length} tokens in ${elapsed.inMilliseconds} ms; '
      'non-standard layouts: ${nonstandard.length}',
    );
    for (final token in nonstandard.take(5)) {
      // ignore: avoid_print
      print(
        'NONSTANDARD surface=${token.surface} '
        'fields=${token.features.length} pos1=${token.pos1} '
        'raw=${token.features.join('|')}',
      );
    }

    expect(tokens.length, greaterThan(100));
    expect(nonstandard, isEmpty);
    expect(tokens.every((token) => token.hasStandardLayout), isTrue);
    expect(tokens.where((token) => token.isContentWord), isNotEmpty);
  });

  testWidgets('reader page renders furigana for 食べた東京', (tester) async {
    expect(dictDir, isNotEmpty);
    await _waitForUnidic(dictDir);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('unidic_path', dictDir);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const RikaiApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查句子'));
    await tester.pumpAndSettle();
    expect(find.text('文本阅读'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '食べた東京');
    await tester.tap(find.text('分词'));

    // The first analysis loads UniDic and spawns the worker isolate; poll in
    // real time instead of pumpAndSettle (the progress bar never settles).
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('たべ').evaluate().isNotEmpty &&
          find.text('とうきょう').evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }

    expect(find.text('食べ'), findsOneWidget);
    expect(find.text('たべ'), findsOneWidget);
    expect(find.text('東京'), findsOneWidget);
    expect(find.text('とうきょう'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.byTooltip('复制全文'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
