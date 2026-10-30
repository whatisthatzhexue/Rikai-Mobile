import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/providers/anthropic_provider.dart';
import 'package:rikai_mobile/services/security/secret_store.dart';

void main() {
  late HttpServer server;
  late String baseUrl;
  Map<String, Object?>? capturedBody;
  Map<String, String> capturedHeaders = <String, String>{};

  setUp(() async {
    capturedBody = null;
    capturedHeaders = <String, String>{};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      capturedHeaders = <String, String>{
        for (final name in <String>[
          'x-api-key',
          'anthropic-version',
          'content-type',
        ])
          if (request.headers.value(name) != null)
            name: request.headers.value(name)!,
      };
      final raw = await utf8.decoder.bind(request).join();
      capturedBody = jsonDecode(raw) as Map<String, Object?>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': '好的'},
          ],
        }),
      );
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sends Messages API text-only request and parses text blocks', () async {
    final secrets = InMemorySecretStore();
    await secrets.write(agentProviderSecretKey('a1'), 'test-key');
    final provider = AnthropicProvider(
      config: AgentProviderConfig(
        id: 'a1',
        kind: AgentProviderKind.anthropic,
        displayName: 'Claude',
        baseUrl: baseUrl,
        smallModel: 'small',
        complexModel: 'large',
        supportsStreaming: false,
        supportsJsonSchema: true,
      ),
      secrets: secrets,
    );

    final events = await provider
        .stream(
          const LlmRequest(
            model: 'large',
            messages: <LlmMessage>[
              LlmMessage(
                role: LlmRole.system,
                parts: <LlmTextPart>[LlmTextPart('system rules')],
              ),
              LlmMessage(
                role: LlmRole.user,
                parts: <LlmTextPart>[LlmTextPart('请翻译')],
              ),
            ],
          ),
        )
        .toList();

    expect(capturedHeaders['x-api-key'], 'test-key');
    expect(capturedHeaders['anthropic-version'], '2026-10-21');
    expect(capturedBody!['system'], 'system rules');
    expect(capturedBody!.containsKey('image'), isFalse);
    expect(capturedBody!.containsKey('temperature'), isFalse);
    expect(events.any((event) => event.type == LlmEventType.done), isTrue);
    expect(events.any((event) => event.text == '好的'), isTrue);
  });
}
