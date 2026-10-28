import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/mdict/entry_cache.dart';
import 'package:rikai_mobile/services/mdict/entry_renderer.dart';

void main() {
  test('get refreshes LRU order and evicts the oldest entry', () {
    final cache = EntryRenderCache(maxEntries: 2);
    const a = RenderedEntry(html: 'a', baseUrl: 'file:///a/');
    const b = RenderedEntry(html: 'b', baseUrl: 'file:///b/');
    const c = RenderedEntry(html: 'c', baseUrl: 'file:///c/');

    cache.put('a', a);
    cache.put('b', b);
    expect(cache.get('a'), same(a));
    expect(cache.length, 2);

    cache.put('c', c);
    expect(cache.get('b'), isNull);
    expect(cache.get('a'), same(a));
    expect(cache.get('c'), same(c));
    expect(cache.length, 2);

    cache.clear();
    expect(cache.length, 0);
  });
}
