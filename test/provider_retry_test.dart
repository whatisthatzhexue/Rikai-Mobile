import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_provider.dart';
import 'package:lexicandy/services/agent/ports/llm_port.dart';
import 'package:lexicandy/services/agent/providers/openai_compatible_provider.dart';
import 'package:lexicandy/services/security/secret_store.dart';

void main() {
  test('retries a 429 once and then succeeds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var attempts = 0;
    server.listen((request) async {
      attempts++;
      await utf8.decoder.bind(request).join();
      if (attempts == 1) {
        request.response.statusCode = 429;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"error":{"message":"rate limited"}}');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': '好的'},
            },
          ],
        }),
      );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final secrets = InMemorySecretStore();
    await secrets.write(agentProviderSecretKey('p-retry'), 'test-key');
    final provider = OpenAiCompatibleProvider(
      config: AgentProviderConfig(
        id: 'p-retry',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'retry',
        baseUrl: 'http://127.0.0.1:${server.port}',
        smallModel: 'small',
        complexModel: 'large',
        supportsStreaming: false,
      ),
      secrets: secrets,
    );

    final observedAttempts = <String>[];
    final events = await provider
        .stream(
          LlmRequest(
            model: 'large',
            messages: <LlmMessage>[
              LlmMessage(
                role: LlmRole.user,
                parts: <LlmTextPart>[LlmTextPart('请翻译')],
              ),
            ],
            onHttpAttempt: (attempt, retry) {
              observedAttempts.add('$attempt:$retry');
            },
          ),
        )
        .toList();

    expect(attempts, 2);
    expect(observedAttempts, <String>['1:false', '2:true']);
    expect(events.any((event) => event.text == '好的'), isTrue);
  });
}
