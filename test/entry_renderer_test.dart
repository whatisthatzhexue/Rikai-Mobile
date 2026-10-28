import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/services/mdict/entry_renderer.dart';

DictionaryInfo _dictionary({List<String> cssPaths = const []}) {
  return DictionaryInfo(
    id: 'dict1',
    title: 'Test Dictionary',
    mdxPath: '/tmp/test.mdx',
    cssPaths: cssPaths,
  );
}

LookupEntry _entry(String html) {
  return LookupEntry(matchedKey: 'test', headword: 'test', html: html);
}

void main() {
  late Directory cache;
  late List<String> loadedKeys;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('rikai_render_');
    loadedKeys = [];
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  test('removes scripts/events and rewrites local MDD images', () async {
    final renderer = EntryRenderer(
      cacheDirectory: cache,
      resourceLoader: (key) async {
        loadedKeys.add(key);
        return Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      },
    );

    final rendered = await renderer.render(
      dictionary: _dictionary(),
      entries: [
        _entry(
          '<script>alert(1)</script>'
          '<div onclick="evil()">安全'
          '<img src="img/a.png" onerror="evil()">'
          '<a href="javascript:alert(1)">bad</a>'
          '<a href="entry://猫">猫</a>'
          '</div>',
        ),
      ],
    );

    expect(rendered.html, isNot(contains('<script')));
    expect(rendered.html, isNot(contains('onclick')));
    expect(rendered.html, isNot(contains('onerror')));
    expect(rendered.html, isNot(contains('javascript:')));
    expect(rendered.html, contains('entry://猫'));
    expect(rendered.html, contains('file://'));
    expect(rendered.html, contains('安全'));
    expect(loadedKeys, contains('img/a.png'));
    expect(rendered.baseUrl, startsWith('file:'));

    final cachedFiles = Directory(
      '${cache.path}/dict1',
    ).listSync().whereType<File>().toList();
    expect(cachedFiles, isNotEmpty);
    expect(await cachedFiles.first.length(), 7);
  });

  test('blocks network images and keeps a placeholder', () async {
    final renderer = EntryRenderer(
      cacheDirectory: cache,
      resourceLoader: (key) async => Uint8List.fromList([1]),
    );

    final rendered = await renderer.render(
      dictionary: _dictionary(),
      entries: [_entry('<img src="https://example.com/a.png">')],
    );

    expect(rendered.html, isNot(contains('example.com')));
    expect(rendered.html, contains('data:image/png;base64'));
    expect(rendered.html, contains('rikai-blocked-resource'));
  });

  test('shows an alt placeholder for missing MDD resources', () async {
    final renderer = EntryRenderer(
      cacheDirectory: cache,
      resourceLoader: (key) async => null,
    );

    final rendered = await renderer.render(
      dictionary: _dictionary(),
      entries: [_entry('<img src="img/missing.png">')],
    );

    expect(rendered.html, contains('data-rikai-missing'));
    expect(rendered.html, contains('[图片缺失]'));
    expect(rendered.html, contains('rikai-missing-resource'));
  });

  test('injects external CSS and rewrites its url() resources', () async {
    final cssFile = File('${cache.path}/dict.css');
    await cssFile.writeAsString(
      '.headline { color: #b71c1c; }'
      '.bg { background: url(img/bg.png); }',
    );
    final renderer = EntryRenderer(
      cacheDirectory: cache,
      resourceLoader: (key) async {
        loadedKeys.add(key);
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final rendered = await renderer.render(
      dictionary: _dictionary(cssPaths: [cssFile.path]),
      entries: [_entry('<div class="headline">東京</div>')],
    );

    expect(rendered.html, contains('.headline'));
    expect(rendered.html, isNot(contains('url(img/bg.png)')));
    expect(rendered.html, contains('file://'));
    expect(loadedKeys, contains('img/bg.png'));
  });

  test('rewrites inline style urls and strips style breakouts', () async {
    final cssFile = File('${cache.path}/evil.css');
    await cssFile.writeAsString(
      'body{color:#000}</style><script>alert(1)</script>',
    );
    final renderer = EntryRenderer(
      cacheDirectory: cache,
      resourceLoader: (key) async {
        loadedKeys.add(key);
        return Uint8List.fromList([1]);
      },
    );

    final rendered = await renderer.render(
      dictionary: _dictionary(cssPaths: [cssFile.path]),
      entries: [_entry('<span style="background:url(img/x.png)">x</span>')],
    );

    expect(rendered.html, isNot(contains('<script')));
    expect(rendered.html, isNot(contains('</style><script')));
    expect(rendered.html, isNot(contains('url(img/x.png)')));
    expect(loadedKeys, contains('img/x.png'));
  });

  test('separates multiple entries with a divider', () async {
    final renderer = EntryRenderer(
      cacheDirectory: cache,
      resourceLoader: (key) async => null,
    );

    final rendered = await renderer.render(
      dictionary: _dictionary(),
      entries: [_entry('<div>第一条</div>'), _entry('<div>第二条</div>')],
    );

    expect(rendered.html, contains('第一条'));
    expect(rendered.html, contains('第二条'));
    expect(rendered.html, contains('rikai-entry-divider'));
  });
}
