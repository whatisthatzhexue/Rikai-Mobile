import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rikai_mobile/core/models/dictionary_scan.dart';
import 'package:rikai_mobile/services/mdict/dictionary_scanner.dart';

void main() {
  test('recursively scans mdx files and discovers siblings', () async {
    final root = await Directory.systemTemp.createTemp('rikai-scan-test-');
    addTearDown(() => root.delete(recursive: true));
    final nested = Directory(p.join(root.path, 'nested'));
    await nested.create();
    final first = File(p.join(root.path, 'First.MDX'));
    await first.writeAsBytes([1, 2, 3]);
    await File(p.join(root.path, 'First.mdd')).writeAsBytes([1]);
    await File(p.join(root.path, 'style.css')).writeAsString('body{}');
    final second = File(p.join(nested.path, 'second.mdx'));
    await second.writeAsBytes([4, 5]);
    await File(p.join(nested.path, 'unrelated.mdd')).writeAsBytes([1]);

    final entries = await const DictionaryScanner().scan(root.path);
    expect(entries, hasLength(2));
    final byName = {for (final entry in entries) entry.fileName: entry};
    expect(byName['First.MDX'], isNotNull);
    expect(byName['First.MDX']!.mddPaths, hasLength(1));
    expect(byName['First.MDX']!.cssPaths, hasLength(1));
    expect(byName['First.MDX']!.status, DictionaryScanStatus.scanning);
    expect(byName['second.mdx']!.mddPaths, isEmpty);

    final existing = await const DictionaryScanner().scan(
      root.path,
      existingPaths: {second.path},
    );
    final existingEntry = existing.firstWhere(
      (entry) => entry.fileName == 'second.mdx',
    );
    expect(existingEntry.status, DictionaryScanStatus.existing);
  });
}
