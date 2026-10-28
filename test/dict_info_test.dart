import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';

void main() {
  test('normalizes paths and derives a stable id', () {
    const path = '/sdcard/Download/dict/dict.mdx';

    expect(
      normalizeDictionaryPath('  file:///sdcard/Download/dict/dict.mdx/  '),
      path,
    );
    expect(
      DictionaryInfo.idForPath('file://$path/'),
      DictionaryInfo.idForPath(path),
    );
    expect(DictionaryInfo.idForPath(path), hasLength(16));
  });

  test('derives a fallback title from the file name', () {
    expect(dictionaryTitleFallback('/sdcard/Download/講談社 大辞典.mdx'), '講談社 大辞典');
    expect(dictionaryFileName(r'C:\dicts\test.mdx'), 'test.mdx');
  });

  test('serializes and restores all fields', () {
    final original = DictionaryInfo(
      id: 'abc123',
      title: 'テスト辞典',
      mdxPath: '/sdcard/dict.mdx',
      mddPaths: const ['/sdcard/dict.mdd'],
      cssPaths: const ['/sdcard/dict.css'],
      entryCount: 463312,
      encoding: 'UTF-8',
      engineVersion: '2.0',
      enabled: false,
      order: 2,
      lastValidatedAt: DateTime.utc(2026, 10, 27, 12, 0),
      lastError: 'missing',
    );

    final restored = DictionaryInfo.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.mdxPath, original.mdxPath);
    expect(restored.mddPaths, original.mddPaths);
    expect(restored.cssPaths, original.cssPaths);
    expect(restored.entryCount, original.entryCount);
    expect(restored.encoding, original.encoding);
    expect(restored.engineVersion, original.engineVersion);
    expect(restored.enabled, isFalse);
    expect(restored.order, 2);
    expect(restored.lastValidatedAt, original.lastValidatedAt);
    expect(restored.lastError, 'missing');
    expect(restored.isAvailable, isFalse);
  });
}
