/// Dictionary lookup matching strategy selected in the title bar.
enum LookupMatchMode { incremental, exact, prefix, suffix }

extension LookupMatchModeLabel on LookupMatchMode {
  String get label => switch (this) {
    LookupMatchMode.incremental => '增量搜索',
    LookupMatchMode.exact => '完全匹配',
    LookupMatchMode.prefix => '前方匹配',
    LookupMatchMode.suffix => '后方匹配',
  };
}

/// Pure key matcher used by the MDict worker and tests.
bool keyMatchesLookupMode(String key, String query, LookupMatchMode mode) {
  if (query.isEmpty) return false;
  return switch (mode) {
    LookupMatchMode.incremental => key.toLowerCase().contains(
      query.toLowerCase(),
    ),
    LookupMatchMode.exact => key == query,
    LookupMatchMode.prefix => key.startsWith(query),
    LookupMatchMode.suffix => key.endsWith(query),
  };
}
