import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/providers/provider_http.dart';
import 'package:rikai_mobile/services/agent/providers/provider_payload.dart';

void main() {
  test('text-only provider payloads pass the guard', () {
    expect(
      () => assertNoImagePayload(<String, Object?>{
        'model': 'test',
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': '何卒宜しくお願い致します。'},
        ],
        'image_id': 'img-1',
        'max_tokens': 100,
      }),
      returnsNormally,
    );
  });

  test('image keys and data URIs are rejected', () {
    expect(
      () => assertNoImagePayload(<String, Object?>{
        'messages': <Object?>[
          <String, Object?>{'image_url': 'https://example.com/a.png'},
        ],
      }),
      throwsA(isA<AgentCapabilityException>()),
    );
    expect(
      () => assertNoImagePayload(<String, Object?>{
        'messages': 'data:image/png;base64,AAAA',
      }),
      throwsA(isA<AgentCapabilityException>()),
    );
  });

  test('local image paths are rejected', () {
    expect(
      () => assertNoImagePayload(<String, Object?>{
        'path': '/sdcard/Download/page.jpg',
      }),
      throwsA(isA<AgentCapabilityException>()),
    );
  });

  test('requested output budget is preserved; only invalid values fail', () {
    const request = LlmRequest(
      model: 'deepseek-chat',
      messages: <LlmMessage>[
        LlmMessage(role: LlmRole.user, parts: <LlmTextPart>[LlmTextPart('何卒')]),
      ],
      maxTokens: 12000,
    );
    expect(validatedProviderMaxTokens(request), 12000);
    expect(
      () => validatedProviderMaxTokens(
        const LlmRequest(model: 'm', messages: <LlmMessage>[], maxTokens: 0),
      ),
      throwsA(isA<AgentCapabilityException>()),
    );
  });

  test('provider text drops unpaired surrogates and control characters', () {
    const input = '何卒\u0000テスト\uD800';
    final sanitized = sanitizeProviderText(input);
    expect(sanitized, '何卒 テスト�');
    expect(sanitizeProviderText('😀'), '😀');

    // Newlines, tabs and carriage returns are meaningful prompt structure and
    // must survive; only C0 controls outside those three are replaced.
    final stats = sanitizeProviderTextWithStats('行1\n行2\t列\r尾\u0000\uD800');
    expect(stats.text, '行1\n行2\t列\r尾 �');
    expect(stats.controlCharacters, 1);
    expect(stats.unpairedSurrogates, 1);
    expect(stats.hasChanges, isTrue);
  });

  test('400 error bodies are classified without assuming a token ceiling', () {
    expect(
      providerBadRequestMessage(
        400,
        'This model maximum context length is 128000 tokens',
      ),
      contains('上下文超限'),
    );
    expect(
      providerBadRequestMessage(
        400,
        'Unsupported parameter: max_tokens is not supported',
      ),
      contains('输出参数'),
    );
    expect(
      providerBadRequestMessage(400, 'reasoning_content is required'),
      contains('思考模式'),
    );
    expect(
      providerBadRequestMessage(400, 'invalid request body'),
      contains('参数无效'),
    );
  });

  test('empty messages and system-only requests are rejected locally', () {
    expect(
      () => validatedProviderMessages(
        const LlmRequest(model: 'm', messages: <LlmMessage>[]),
      ),
      throwsA(isA<AgentCapabilityException>()),
    );
    expect(
      () => validatedProviderMessages(
        const LlmRequest(
          model: 'm',
          messages: <LlmMessage>[
            LlmMessage(
              role: LlmRole.system,
              parts: <LlmTextPart>[LlmTextPart('rules')],
            ),
          ],
        ),
      ),
      throwsA(isA<AgentCapabilityException>()),
    );
    final filtered = validatedProviderMessages(
      const LlmRequest(
        model: 'm',
        messages: <LlmMessage>[
          LlmMessage(
            role: LlmRole.system,
            parts: <LlmTextPart>[LlmTextPart('  ')],
          ),
          LlmMessage(
            role: LlmRole.user,
            parts: <LlmTextPart>[LlmTextPart('请翻译')],
          ),
        ],
      ),
    );
    expect(filtered, hasLength(1));
    expect(filtered.single.role, LlmRole.user);
  });
}
