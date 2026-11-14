/// Deterministic, bounded probes for dictionary familiarization.
class DictionaryProbeSet {
  const DictionaryProbeSet({required this.exact, required this.prefix});

  final List<String> exact;
  final List<String> prefix;

  static const DictionaryProbeSet builtIn = DictionaryProbeSet(
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
          : builtIn.exact,
      prefix: prefix is List
          ? prefix.whereType<String>().toList(growable: false)
          : builtIn.prefix,
    );
  }
}
