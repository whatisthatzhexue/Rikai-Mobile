import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/services/mdict/entry_renderer.dart';
import 'package:rikai_mobile/services/mdict/mdict_worker.dart';

const String _root = '/sdcard/Download/rikai-mdict-audio';
const String _query = 'あくまで';

Future<void> _waitForDictionary() async {
  final mdx = File('$_root/dict.mdx');
  final mdd = File('$_root/dict.mdd');
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
  fail('Audio dictionary files are not readable under $_root');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders MDD sound:// links as local audio players', (
    tester,
  ) async {
    await _waitForDictionary();
    final service = await MdictService.open();
    addTearDown(service.dispose);

    final mdxPath = '$_root/dict.mdx';
    final metadata = await service.probe(mdxPath);
    final info = DictionaryInfo(
      id: DictionaryInfo.idForPath(mdxPath),
      title: metadata.title,
      mdxPath: mdxPath,
      mddPaths: ['$_root/dict.mdd'],
      entryCount: metadata.entryCount,
      encoding: metadata.encoding,
      engineVersion: metadata.engineVersion,
      lastValidatedAt: DateTime.now(),
    );

    final result = await service.lookup(
      query: _query,
      rawCandidates: const [_query],
      dictionaries: [info],
    );
    expect(result.hasHits, isTrue);
    final entry = result.hitGroups.first.entries.first;
    final match = RegExp(
      r'''sound://([^"'\s>]+)''',
      caseSensitive: false,
    ).firstMatch(entry.html);
    expect(
      match,
      isNotNull,
      reason: 'entry should reference an MDD audio file',
    );
    final audioKey = match!.group(1)!;
    final bytes = await service.readResource(dictionary: info, key: audioKey);
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(1000));

    final cacheRoot = await getApplicationCacheDirectory();
    final renderer = EntryRenderer(
      cacheDirectory: Directory('${cacheRoot.path}/mdict-audio-test'),
      resourceLoader: (key) => service.readResource(dictionary: info, key: key),
    );
    final rendered = await renderer.render(dictionary: info, entries: [entry]);
    expect(rendered.html, contains('<audio'));
    expect(rendered.html, contains('file://'));
    expect(rendered.html, isNot(contains('sound://')));

    // ignore: avoid_print
    print(
      'audio dictionary "${metadata.title}" key=$audioKey '
      'bytes=${bytes.length} html=${rendered.html.length}',
    );
  });
}
