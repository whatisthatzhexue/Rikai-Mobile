import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_provider.dart';
import 'package:lexicandy/core/models/agent/agent_tool.dart';
import 'package:lexicandy/services/agent/agent_provider_tester.dart';
import 'package:lexicandy/services/agent/ports/agent_capability_exception.dart';
import 'package:lexicandy/services/agent/ports/llm_port.dart';
import 'package:lexicandy/services/agent/ports/secret_port.dart';

const _config = AgentProviderConfig(
  id: 'p1',
  kind: AgentProviderKind.openAiCompatible,
  displayName: 'Test',
  baseUrl: 'https://example.com/v1',
  smallModel: 'small-model',
  complexModel: 'complex-model',
);

class _MemorySecret implements SecretPort {
  _MemorySecret(this.value);

  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }

  @override
  Future<void> delete(String key) async {
    value = null;
  }
}

class _FakeLlm implements LlmPort {
  _FakeLlm({this.error});

  final AgentCapabilityException? error;
  LlmRequest? request;
  SecretPort? secrets;

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    this.request = request;
    if (error != null) throw error!;
    yield const LlmEvent(type: LlmEventType.textDelta, text: 'OK');
    yield LlmEvent.done();
  }
}

void main() {
  test(
    'uses a minimal non-streaming request with no automatic retry',
    () async {
      final fake = _FakeLlm();
      final tester = AgentProviderTester(
        secrets: _MemorySecret('stored-key'),
        llmFactory: (config, secrets) {
          fake.secrets = secrets;
          return fake;
        },
      );

      final result = await tester.test(config: _config);

      expect(result.ok, isTrue);
      expect(result.model, 'small-model');
      expect(fake.request, isNotNull);
      expect(fake.request!.model, 'small-model');
      expect(fake.request!.stream, isFalse);
      expect(fake.request!.maxHttpAttempts, 1);
      expect(fake.request!.maxTokens, 16);
      expect(fake.request!.messages.first.role, LlmRole.system);
      expect(fake.request!.messages.last.role, LlmRole.user);
      expect(await fake.secrets!.read('unused'), 'stored-key');
    },
  );

  test('uses the unsaved form key without changing the stored key', () async {
    final fake = _FakeLlm();
    final stored = _MemorySecret('stored-key');
    final tester = AgentProviderTester(
      secrets: stored,
      llmFactory: (config, secrets) {
        fake.secrets = secrets;
        return fake;
      },
    );

    await tester.test(config: _config, apiKey: 'form-key');

    expect(await fake.secrets!.read('unused'), 'form-key');
    expect(stored.value, 'stored-key');
  });

  test(
    'falls back to the complex model when the small model is empty',
    () async {
      final fake = _FakeLlm();
      final tester = AgentProviderTester(
        secrets: _MemorySecret('key'),
        llmFactory: (config, secrets) => fake,
      );

      final result = await tester.test(
        config: _config.copyWith(smallModel: ''),
      );

      expect(result.ok, isTrue);
      expect(result.model, 'complex-model');
    },
  );

  test('maps provider auth failures without exposing the key', () async {
    final fake = _FakeLlm(
      error: const AgentCapabilityException(
        AgentToolErrorCode.providerAuthFailed,
        'API Key 无效',
      ),
    );
    final tester = AgentProviderTester(
      secrets: _MemorySecret('secret-key'),
      llmFactory: (config, secrets) => fake,
    );

    final result = await tester.test(config: _config);

    expect(result.ok, isFalse);
    expect(result.errorCode, AgentToolErrorCode.providerAuthFailed);
    expect(result.message, isNot(contains('secret-key')));
  });

  test('reports not configured when both models are empty', () async {
    final tester = AgentProviderTester(
      secrets: _MemorySecret('key'),
      llmFactory: (config, secrets) => _FakeLlm(),
    );

    final result = await tester.test(
      config: _config.copyWith(smallModel: '', complexModel: ''),
    );

    expect(result.ok, isFalse);
    expect(result.errorCode, AgentToolErrorCode.notConfigured);
  });
}
