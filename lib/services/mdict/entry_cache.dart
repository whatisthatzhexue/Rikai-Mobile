import 'dart:collection';

import 'entry_renderer.dart';

/// Small in-memory LRU cache for rendered dictionary entries.
///
/// Navigating back and forth between the same word now reuses the cleaned
/// HTML and local resource URLs instead of re-reading CSS and MDD files.
class EntryRenderCache {
  EntryRenderCache({this.maxEntries = 24});

  final int maxEntries;
  final LinkedHashMap<String, RenderedEntry> _entries = LinkedHashMap();

  int get length => _entries.length;

  RenderedEntry? get(String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void put(String key, RenderedEntry value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
