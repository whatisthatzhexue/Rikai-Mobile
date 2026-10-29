import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/services/mdict/entry_renderer.dart';
import 'package:rikai_mobile/services/mdict/mdict_worker.dart';

const String _root = '/sdcard/Download/rikai-mdict-compat';

Future<void> _waitForDictionary(String folder) async {
  final mdx = File('$_root/$folder/dict.mdx');
  final mdd = File('$_root/$folder/dict.mdd');
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await mdx.exists() &&
          await mdd.exists() &&
          await mdx.length() > 0 &&
          await mdd.length() > 0) {
        return;
      }
    } catch (_) {
      // The host grants All Files Access in a loop while the test runs.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Dictionary files are not readable under $_root/$folder');
}

Future<DictionaryInfo> _probe(MdictService service, String folder) async {
  final mdxPath = '$_root/$folder/dict.mdx';
  final metadata = await service.probe(mdxPath);
  return DictionaryInfo(
    id: DictionaryInfo.idForPath(mdxPath),
    title: metadata.title,
    mdxPath: mdxPath,
    mddPaths: ['$_root/$folder/dict.mdd'],
    cssPaths: ['$_root/$folder/dict.css'],
    entryCount: metadata.entryCount,
    encoding: metadata.encoding,
    engineVersion: metadata.engineVersion,
    lastValidatedAt: DateTime.now(),
  );
}

String? _firstImage(String html) {
  final match = RegExp(
    r'''<img[^>]+src\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  return match?.group(1);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens Encrypted=2 dictionary and reads its MDD image', (
    tester,
  ) async {
    await _waitForDictionary('kanjigen');
    final service = await MdictService.open();
    addTearDown(service.dispose);
    final info = await _probe(service, 'kanjigen');
    expect(info.title, contains('漢字源'));
    expect(info.entryCount, 84396);
    expect(info.engineVersion, startsWith('2.'));

    final result = await service.lookup(
      query: '0凡例',
      rawCandidates: const ['0凡例'],
      dictionaries: [info],
    );
    expect(result.hasHits, isTrue);
    final entry = result.hitGroups.first.entries.first;
    final imageKey = _firstImage(entry.html);
    expect(imageKey, isNotNull);
    final bytes = await service.readResource(dictionary: info, key: imageKey!);
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(8));
    // ignore: avoid_print
    print(
      'kanjigen Encrypted=2 entries=${info.entryCount} '
      'image=$imageKey bytes=${bytes.length}',
    );

    final cacheRoot = await getApplicationCacheDirectory();
    final renderer = EntryRenderer(
      cacheDirectory: Directory('${cacheRoot.path}/mdict-compat-kanjigen'),
      resourceLoader: (key) => service.readResource(dictionary: info, key: key),
    );
    final rendered = await renderer.render(dictionary: info, entries: [entry]);
    expect(rendered.html, contains('file://'));
  });

  testWidgets('reads a non-encrypted dictionary MDD image', (tester) async {
    await _waitForDictionary('meikyo');
    final service = await MdictService.open();
    addTearDown(service.dispose);
    final info = await _probe(service, 'meikyo');
    expect(info.title, contains('明鏡'));
    expect(info.entryCount, 403495);

    final result = await service.lookup(
      query: '00001',
      rawCandidates: const ['00001'],
      dictionaries: [info],
    );
    expect(result.hasHits, isTrue);
    final entry = result.hitGroups.first.entries.first;
    final imageKey = _firstImage(entry.html);
    expect(imageKey, isNotNull);
    final bytes = await service.readResource(dictionary: info, key: imageKey!);
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(8));
    // ignore: avoid_print
    print(
      'meikyo entries=${info.entryCount} image=$imageKey bytes=${bytes.length}',
    );
  });
}
