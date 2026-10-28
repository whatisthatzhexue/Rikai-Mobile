import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/services/mdict/entry_renderer.dart';
import 'package:rikai_mobile/services/mdict/mdict_worker.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _mdxPath = String.fromEnvironment(
  'RIKAI_MDICT_PATH',
  defaultValue: '/sdcard/Download/rikai-mdict/dict.mdx',
);
const String _mddPath = '/sdcard/Download/rikai-mdict/dict.mdd';
const String _cssPath = '/sdcard/Download/rikai-mdict/dict.css';

Future<void> _waitForFiles() async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    RandomAccessFile? handle;
    try {
      handle = await File(_mdxPath).open();
      final header = await handle.read(4);
      if (header.length == 4 && await File(_mddPath).exists()) return;
    } catch (_) {
      // Permission may not be granted yet; the host grants it in a loop.
    } finally {
      await handle?.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('MDict files are not readable at $_mdxPath after 120s');
}

Future<({DictionaryInfo info, DictionaryMetadata metadata})> _probe(
  MdictService service,
) async {
  final metadata = await service.probe(_mdxPath);
  final info = DictionaryInfo(
    id: DictionaryInfo.idForPath(_mdxPath),
    title: metadata.title,
    mdxPath: _mdxPath,
    mddPaths: const [_mddPath],
    cssPaths: const [_cssPath],
    entryCount: metadata.entryCount,
    encoding: metadata.encoding,
    engineVersion: metadata.engineVersion,
    lastValidatedAt: DateTime.now(),
  );
  return (info: info, metadata: metadata);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the real MDX and reports metadata', (tester) async {
    await _waitForFiles();

    final opened = Stopwatch()..start();
    final service = await MdictService.open();
    addTearDown(service.dispose);
    final probeWatch = Stopwatch()..start();
    final probed = await _probe(service);
    probeWatch.stop();
    opened.stop();

    // ignore: avoid_print
    print(
      'MdictService.open=${opened.elapsedMilliseconds}ms '
      'probe=${probeWatch.elapsedMilliseconds}ms '
      'title=${probed.metadata.title} entries=${probed.metadata.entryCount} '
      'encoding=${probed.metadata.encoding} '
      'version=${probed.metadata.engineVersion}',
    );

    expect(probed.metadata.title, contains('講談社'));
    expect(probed.metadata.entryCount, 463312);
    expect(probed.metadata.encoding.toUpperCase(), 'UTF-8');
    expect(probed.metadata.engineVersion, startsWith('2.'));
    expect(probed.metadata.fileSize, greaterThan(30 * 1024 * 1024));
  });

  testWidgets('lookup resolves @@@LINK and returns suggestions', (
    tester,
  ) async {
    await _waitForFiles();
    final service = await MdictService.open();
    addTearDown(service.dispose);
    final probed = await _probe(service);
    final info = probed.info;

    final watch = Stopwatch()..start();
    final tokyo = await service.lookup(
      query: '東京',
      rawCandidates: const ['東京'],
      dictionaries: [info],
    );
    watch.stop();

    expect(tokyo.hasHits, isTrue);
    final entry = tokyo.hitGroups.first.entries.first;
    // ignore: avoid_print
    print(
      'lookup 東京=${watch.elapsedMilliseconds}ms '
      'matched=${entry.matchedKey} headword=${entry.headword} '
      'html=${entry.html.length} candidates=${tokyo.candidates.length}',
    );
    expect(entry.matchedKey, '東京');
    expect(entry.headword, contains('東京'));
    expect(entry.html, isNot(contains('@@@LINK')));
    expect(entry.html, contains('とうきょう'));

    final hotWatch = Stopwatch()..start();
    final hot = await service.lookup(
      query: '東京',
      rawCandidates: const ['東京'],
      dictionaries: [info],
    );
    hotWatch.stop();
    expect(hot.hasHits, isTrue);
    // ignore: avoid_print
    print('hot lookup 東京=${hotWatch.elapsedMilliseconds}ms');

    final taberu = await service.lookup(
      query: '食べる',
      rawCandidates: const ['食べる'],
      dictionaries: [info],
    );
    expect(taberu.hasHits, isTrue);
    expect(taberu.hitGroups.first.entries.first.html, contains('食べる'));

    final kana = await service.lookup(
      query: 'とうきょう',
      rawCandidates: const ['とうきょう'],
      dictionaries: [info],
    );
    expect(kana.hasHits, isTrue);

    final prefix = await service.lookup(
      query: 'とうきょうえ',
      rawCandidates: const ['とうきょうえ'],
      dictionaries: [info],
      suggestionLimit: 10,
    );
    expect(prefix.hasHits, isFalse);
    expect(prefix.suggestions, isNotEmpty);
    // ignore: avoid_print
    print('suggestions=${prefix.suggestions.take(5).toList()}');
  });

  testWidgets('warm-up removes the first lookup cold start', (tester) async {
    await _waitForFiles();
    final service = await MdictService.open();
    addTearDown(service.dispose);
    final probed = await _probe(service);

    final warmUpWatch = Stopwatch()..start();
    await service.warmUp([probed.info]);
    warmUpWatch.stop();

    final lookupWatch = Stopwatch()..start();
    final result = await service.lookup(
      query: '東京',
      rawCandidates: const ['東京'],
      dictionaries: [probed.info],
    );
    lookupWatch.stop();

    expect(result.hasHits, isTrue);
    // ignore: avoid_print
    print(
      'warmUp=${warmUpWatch.elapsedMilliseconds}ms '
      'firstLookupAfterWarmUp=${lookupWatch.elapsedMilliseconds}ms',
    );
    expect(lookupWatch.elapsedMilliseconds, lessThan(200));
  });

  testWidgets('reads MDD images and renders a clean entry', (tester) async {
    await _waitForFiles();
    final service = await MdictService.open();
    addTearDown(service.dispose);
    final probed = await _probe(service);

    final result = await service.lookup(
      query: '猫',
      rawCandidates: const ['猫'],
      dictionaries: [probed.info],
      maxEntriesPerDictionary: 3,
    );
    expect(result.hasHits, isTrue);
    final entries = result.hitGroups.first.entries;
    expect(entries, isNotEmpty);

    String? imageKey;
    for (final entry in entries) {
      final match = RegExp(r'src="([^"]+)"').firstMatch(entry.html);
      if (match != null) {
        imageKey = match.group(1);
        break;
      }
    }
    expect(imageKey, isNotNull, reason: 'expected an MDD image in 猫');

    final bytes = await service.readResource(
      dictionary: probed.info,
      key: imageKey!,
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(8));
    expect(bytes.take(4).toList(), [137, 80, 78, 71]);
    // ignore: avoid_print
    print('resource $imageKey -> ${bytes.length} bytes');

    final cacheRoot = await getApplicationCacheDirectory();
    final renderer = EntryRenderer(
      cacheDirectory: Directory('${cacheRoot.path}/rikai-mdict-test'),
      resourceLoader: (key) =>
          service.readResource(dictionary: probed.info, key: key),
    );
    final rendered = await renderer.render(
      dictionary: probed.info,
      entries: entries,
    );

    expect(rendered.html, contains('rikai-entry-body'));
    expect(rendered.html, contains('file://'));
    expect(rendered.html, contains('.headline'));
    expect(rendered.html, isNot(contains('<script')));
    // ignore: avoid_print
    print('rendered ${entries.length} entries, html=${rendered.html.length}');
  });

  testWidgets('repository adds the dictionary in place', (tester) async {
    await _waitForFiles();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('mdict_dictionaries_v1');
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final info = await container
        .read(dictionaryRepositoryProvider.notifier)
        .addDictionary(_mdxPath);

    expect(info.entryCount, 463312);
    expect(info.mddPaths, contains(_mddPath));
    expect(info.cssPaths, contains(_cssPath));
    expect(info.isAvailable, isTrue);
    expect(container.read(enabledDictionariesProvider), hasLength(1));
    expect(
      preferences.getString('mdict_dictionaries_v1'),
      contains('dict.mdx'),
    );
    // ignore: avoid_print
    print('repository: ${info.title} ${info.entryCount} entries');
  });

  testWidgets('search page opens a dictionary entry with the real MDict', (
    tester,
  ) async {
    await _waitForFiles();

    // Seed the registry so this test also works when run alone.
    final service = await MdictService.open();
    final probed = await _probe(service);
    await service.dispose();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'mdict_dictionaries_v1',
      jsonEncode([probed.info.toJson()]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const RikaiApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查词'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '東京');
    await tester.tap(find.byTooltip('查询'));

    final resultDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(resultDeadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('とうきょう【東京】').evaluate().isNotEmpty) break;
    }
    expect(find.text('とうきょう【東京】'), findsOneWidget);

    await tester.tap(find.text('とうきょう【東京】'));
    await tester.pump();

    final webViewDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(webViewDeadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(InAppWebView).evaluate().isNotEmpty) break;
    }
    expect(find.byType(InAppWebView), findsOneWidget);
    expect(find.text('東京'), findsWidgets);
  });
}
