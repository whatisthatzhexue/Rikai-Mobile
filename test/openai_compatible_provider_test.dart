import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/agent/agent_tool.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/providers/openai_compatible_provider.dart';
import 'package:rikai_mobile/services/security/secret_store.dart';

void main() {
  late HttpServer server;
  late String baseUrl;
  Map<String, Object?>? capturedBody;
  String? capturedAuthorization;
  String? streamBody;
  var streamResponse = false;
  var requestCount = 0;

  setUp(() async {
    capturedBody = null;
    capturedAuthorization = null;
    streamBody = null;
    streamResponse = false;
    requestCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      requestCount++;
      capturedAuthorization = request.headers.value('authorization');
      final raw = await utf8.decoder.bind(request).join();
      capturedBody = jsonDecode(raw) as Map<String, Object?>;
      if (streamResponse) {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          streamBody ??
              'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
                  'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
                  'data: [DONE]\n\n',
        );
        await request.response.flush();
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
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sends a text-only request and parses a non-streaming reply', () async {
    final secrets = InMemorySecretStore();
    await secrets.write(agentProviderSecretKey('p1'), 'test-key');
    final provider = OpenAiCompatibleProvider(
      config: AgentProviderConfig(
        id: 'p1',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'Test',
        baseUrl: baseUrl,
        smallModel: 'small',
        complexModel: 'large',
        supportsStreaming: false,
      ),
      secrets: secrets,
    );

    final events = await provider
        .stream(
          const LlmRequest(
            model: 'large',
            maxTokens: 12000,
            messages: <LlmMessage>[
              LlmMessage(
                role: LlmRole.user,
                parts: <LlmTextPart>[LlmTextPart('请翻译')],
              ),
            ],
          ),
        )
        .toList();

    expect(capturedAuthorization, 'Bearer test-key');
    expect(capturedBody!['model'], 'large');
    expect(capturedBody!.containsKey('max_tokens'), isFalse);
    expect(capturedBody!.containsKey('image'), isFalse);
    expect(capturedBody!.containsKey('image_url'), isFalse);
    expect(capturedBody!['stream'], isFalse);
    expect(capturedBody!.containsKey('response_format'), isFalse);
    expect(
      events.whereType<LlmEvent>().any(
        (event) => event.type == LlmEventType.done,
      ),
      isTrue,
    );
    expect(events.any((event) => event.text == '好的'), isTrue);
  });

  test('streams SSE text deltas from a Uint8List response body', () async {
    streamResponse = true;
    final secrets = InMemorySecretStore();
    await secrets.write(agentProviderSecretKey('p3'), 'test-key');
    final provider = OpenAiCompatibleProvider(
      config: AgentProviderConfig(
        id: 'p3',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'Test',
        baseUrl: baseUrl,
        smallModel: 'small',
        complexModel: 'large',
        supportsStreaming: true,
      ),
      secrets: secrets,
    );

    final events = await provider
        .stream(
          const LlmRequest(
            model: 'large',
            maxTokens: 12000,
            messages: <LlmMessage>[
              LlmMessage(
                role: LlmRole.user,
                parts: <LlmTextPart>[LlmTextPart('请翻译')],
              ),
            ],
          ),
        )
        .toList();

    expect(capturedBody!['stream'], isTrue);
    expect(capturedBody!.containsKey('max_tokens'), isFalse);
    expect(
      events
          .where((event) => event.type == LlmEventType.textDelta)
          .map((event) => event.text)
          .join(),
      '你好',
    );
    expect(events.last.type, LlmEventType.done);
  });

  test('reasoning-only stream fails once instead of retrying', () async {
    streamResponse = true;
    streamBody =
        'data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n'
        'data: [DONE]\n\n';
    final secrets = InMemorySecretStore();
    await secrets.write(agentProviderSecretKey('p4'), 'test-key');
    final provider = OpenAiCompatibleProvider(
      config: AgentProviderConfig(
        id: 'p4',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'Test',
        baseUrl: baseUrl,
        smallModel: 'small',
        complexModel: 'large',
        supportsStreaming: true,
      ),
      secrets: secrets,
    );

    await expectLater(
      provider
          .stream(
            const LlmRequest(
              model: 'large',
              maxTokens: 12000,
              messages: <LlmMessage>[
                LlmMessage(
                  role: LlmRole.user,
                  parts: <LlmTextPart>[LlmTextPart('请翻译')],
                ),
              ],
            ),
          )
          .toList(),
      throwsA(
        isA<AgentCapabilityException>().having(
          (error) => error.code,
          'code',
          AgentToolErrorCode.providerEmptyOutput,
        ),
      ),
    );
    expect(requestCount, 1);
  });

  test('missing API key fails before sending a request', () async {
    final provider = OpenAiCompatibleProvider(
      config: AgentProviderConfig(
        id: 'p2',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'Test',
        baseUrl: baseUrl,
        smallModel: 'small',
        complexModel: 'large',
      ),
      secrets: InMemorySecretStore(),
    );

    await expectLater(
      provider
          .stream(
            const LlmRequest(
              model: 'large',
              messages: <LlmMessage>[
                LlmMessage(
                  role: LlmRole.user,
                  parts: <LlmTextPart>[LlmTextPart('hello')],
                ),
              ],
            ),
          )
          .toList(),
      throwsA(isA<AgentCapabilityException>()),
    );
    expect(capturedBody, isNull);
  });
}
