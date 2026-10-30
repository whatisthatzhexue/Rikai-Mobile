import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Deterministic, bounded probes for dictionary familiarization.
class DictionaryProbeSet {
  const DictionaryProbeSet({required this.exact, required this.prefix});

  final List<String> exact;
  final List<String> prefix;

  static const DictionaryProbeSet fallback = DictionaryProbeSet(
    exact: <String>[
      'ありがとう',
      '食べる',
      '行く',
      '美しい',
      '日本',
      '勉強',
      'コンピューター',
      'は',
      'こと',
      'です',
      'ます',
      'ない',
    ],
    prefix: <String>['あ', 'か', 'さ', '漢', '日本', 'A', '1'],
  );

  factory DictionaryProbeSet.fromJson(Map<String, Object?> json) {
    final exact = json['exact'];
    final prefix = json['prefix'];
    return DictionaryProbeSet(
      exact: exact is List
          ? exact.whereType<String>().toList(growable: false)
          : fallback.exact,
      prefix: prefix is List
          ? prefix.whereType<String>().toList(growable: false)
          : fallback.prefix,
    );
  }
}

Future<DictionaryProbeSet> loadDictionaryProbes({
  AssetBundle? bundle,
  String path = 'assets/agent/dictionary_probes.json',
}) async {
  try {
    final raw = await (bundle ?? rootBundle).loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return DictionaryProbeSet.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  } catch (_) {
    // Missing/invalid asset is non-fatal; use the bounded fallback.
  }
  return DictionaryProbeSet.fallback;
}
