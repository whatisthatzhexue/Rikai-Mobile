import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_probes.dart';

void main() {
  test('probe JSON overrides the bounded fallback', () {
    final probes = DictionaryProbeSet.fromJson(<String, Object?>{
      'exact': <String>['ありがとう', '食べる'],
      'prefix': <String>['あ', '漢'],
    });
    expect(probes.exact, ['ありがとう', '食べる']);
    expect(probes.prefix, ['あ', '漢']);
  });

  test('malformed probe JSON keeps the fallback lists', () {
    final probes = DictionaryProbeSet.fromJson(const <String, Object?>{});
    expect(probes.exact, DictionaryProbeSet.fallback.exact);
    expect(probes.prefix, DictionaryProbeSet.fallback.prefix);
    expect(probes.exact, isNotEmpty);
    expect(probes.prefix, isNotEmpty);
  });
}
