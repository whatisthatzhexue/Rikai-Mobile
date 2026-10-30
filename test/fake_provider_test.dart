import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_mobile/services/security/secret_store.dart';

const _request = LlmRequest(
  model: 'small',
  messages: <LlmMessage>[
    LlmMessage(role: LlmRole.user, parts: <LlmTextPart>[LlmTextPart('hello')]),
  ],
);

void main() {
  test('fake provider records the text-only request', () async {
    final provider = FakeProvider(responseText: 'ok');
    final events = await provider.stream(_request).toList();

    expect(provider.requests, hasLength(1));
    expect(provider.requests.single.messages.single.text, 'hello');
    expect(events.first.type, LlmEventType.textDelta);
    expect(events.first.text, 'ok');
    expect(events.last.type, LlmEventType.done);
  });

  test('in-memory secret store supports write/read/delete', () async {
    final store = InMemorySecretStore();
    expect(await store.read('k'), isNull);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });
}
