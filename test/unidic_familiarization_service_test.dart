import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_repository.dart';
import 'package:rikai_mobile/services/agent/familiarization/unidic_familiarization_service.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';

class _FakeTokenizePort implements TokenizePort {
  int calls = 0;

  @override
  Future<List<Token>> analyze(String text) async {
    calls++;
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '名詞';
    features[7] = 'テスト';
    features[8] = 'テスト';
    features[20] = 'テスト';
    return <Token>[
      Token.fromFeatures(surface: 'テスト', features: features, start: 0, end: 3),
    ];
  }
}

void main() {
  test('deterministic UniDic profile is generated and reused', () async {
    final port = _FakeTokenizePort();
    final repository = InMemoryUnidicProfileRepository();
    final service = UnidicFamiliarizationService(
      tokenizePort: port,
      repository: repository,
    );

    final first = await service.ensure('/tmp/rikai-unidic');
    expect(first, isNotNull);
    expect(first!.featureLayout, Token.expectedFeatureCount);
    expect(first.observations, isNotEmpty);
    expect(port.calls, 4);

    final second = await service.ensure('/tmp/rikai-unidic');
    expect(second!.featureLayout, Token.expectedFeatureCount);
    expect(port.calls, 4);
  });
}
