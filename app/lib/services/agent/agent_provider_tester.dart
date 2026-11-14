import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_tool.dart';
import 'ports/agent_capability_exception.dart';
import 'agent_task_route.dart';
import 'ports/llm_port.dart';
import 'ports/secret_port.dart';
import 'providers/provider_factory.dart';

/// Result of an explicit, user-triggered provider connectivity test.
///
/// The tester never writes history or changes provider configuration. API keys
/// and request bodies are never included in [message] or logs.
class AgentProviderTestResult {
  const AgentProviderTestResult({
    required this.ok,
    this.latencyMs = 0,
    this.model = '',
    this.errorCode,
    this.message = '',
  });

  final bool ok;
  final int latencyMs;
  final String model;
  final AgentToolErrorCode? errorCode;
  final String message;
}

typedef ProviderTestLlmFactory =
    LlmPort Function(AgentProviderConfig config, SecretPort secrets);

/// One minimal text-only request used by the provider settings "test
/// connection" action.
///
/// It reuses the production provider adapters, payload validation and error
/// mapping, but sends no images, tools, schema, history or citations, and makes
/// exactly one HTTP attempt (no automatic retry).
class AgentProviderTester {
  const AgentProviderTester({
    required this.secrets,
    ProviderTestLlmFactory? llmFactory,
  }) : _llmFactory = llmFactory;

  final SecretPort secrets;
  final ProviderTestLlmFactory? _llmFactory;

  Future<AgentProviderTestResult> test({
    required AgentProviderConfig config,
    String apiKey = '',
  }) async {
    final model = AgentTaskRoute.resolve(
      AgentTaskKind.providerTest,
      config,
    ).model;
    if (model.isEmpty) {
      return const AgentProviderTestResult(
        ok: false,
        errorCode: AgentToolErrorCode.notConfigured,
      );
    }

    final suppliedKey = apiKey.trim();
    final effectiveSecrets = suppliedKey.isEmpty
        ? secrets
        : _FixedSecretPort(suppliedKey);
    final factory =
        _llmFactory ??
        (provider, port) => createLlmProvider(config: provider, secrets: port);
    final llm = factory(config, effectiveSecrets);

    final request = LlmRequest(
      model: model,
      messages: const <LlmMessage>[
        LlmMessage(
          role: LlmRole.system,
          parts: <LlmTextPart>[
            LlmTextPart('You are a connectivity test. Reply briefly.'),
          ],
        ),
        LlmMessage(
          role: LlmRole.user,
          parts: <LlmTextPart>[LlmTextPart('Reply with OK.')],
        ),
      ],
      maxTokens: 16,
      stream: false,
      maxHttpAttempts: 1,
    );
    final watch = Stopwatch()..start();
    try {
      await for (final event in llm.stream(request)) {
        if (event.type == LlmEventType.error) {
          return AgentProviderTestResult(
            ok: false,
            errorCode: AgentToolErrorCode.providerUnavailable,
          );
        }
        if (event.type == LlmEventType.done) break;
      }
      return AgentProviderTestResult(
        ok: true,
        latencyMs: watch.elapsedMilliseconds,
        model: model,
      );
    } on AgentCapabilityException catch (error) {
      return AgentProviderTestResult(
        ok: false,
        latencyMs: watch.elapsedMilliseconds,
        model: model,
        errorCode: error.code,
        message: error.message,
      );
    } catch (_) {
      return AgentProviderTestResult(
        ok: false,
        latencyMs: watch.elapsedMilliseconds,
        model: model,
        errorCode: AgentToolErrorCode.providerUnavailable,
      );
    }
  }
}

class _FixedSecretPort implements SecretPort {
  const _FixedSecretPort(this.value);

  final String value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
