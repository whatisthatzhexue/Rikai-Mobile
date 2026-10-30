import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
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
}
