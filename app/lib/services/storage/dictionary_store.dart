import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/dict_info.dart';

/// Persists the user's dictionary registry as JSON. MDict files themselves are
/// never copied; only paths and metadata are stored.
class DictionaryStore {
  const DictionaryStore(this._preferences);

  static const _key = 'mdict_dictionaries_v1';

  final SharedPreferences _preferences;

  List<DictionaryInfo> load() {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final dictionaries = <DictionaryInfo>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final info = DictionaryInfo.fromJson(Map<String, Object?>.from(item));
        if (info.id.isEmpty || info.mdxPath.isEmpty) continue;
        dictionaries.add(info);
      }
      return dictionaries;
    } catch (_) {
      // A corrupt registry should not prevent the app from starting.
      return const [];
    }
  }

  Future<void> save(List<DictionaryInfo> dictionaries) async {
    final encoded = jsonEncode(
      dictionaries.map((dictionary) => dictionary.toJson()).toList(),
    );
    await _preferences.setString(_key, encoded);
  }
}
