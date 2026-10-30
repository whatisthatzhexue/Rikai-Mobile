/// Small, dependency-free helpers for the Agent JSON contracts.
///
/// Agent wire models use snake_case keys (see `docs/phase6-agent-contracts.md`);
/// these helpers keep `fromJson` implementations tolerant of missing fields and
/// isolate the casts in one place.
List<String> agentStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

Map<String, Object?> agentMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String agentString(Object? value, [String fallback = '']) {
  return value is String ? value : fallback;
}

int agentInt(Object? value, [int fallback = 0]) {
  return value is num ? value.toInt() : fallback;
}

double agentDouble(Object? value, [double fallback = 0]) {
  return value is num ? value.toDouble() : fallback;
}

bool agentBool(Object? value, [bool fallback = false]) {
  return value is bool ? value : fallback;
}
