import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_tool.dart';
import 'package:rikai_mobile/services/agent/providers/provider_http.dart';

void main() {
  test('parses SSE data from Dio-style Uint8List chunks', () async {
    final payload = utf8.encode(
      'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
      'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
      'data: [DONE]\n\n',
    );
    final events = await sseDataEvents(
      Stream<Uint8List>.fromIterable(<Uint8List>[
        Uint8List.fromList(payload.sublist(0, 17)),
        Uint8List.fromList(payload.sublist(17)),
      ]),
    ).toList();

    expect(events, hasLength(2));
    expect(events.first, contains('"你"'));
    expect(events.last, contains('"好"'));
  });

  test('reassembles an SSE event split across multiple data lines', () async {
    final payload = utf8.encode(
      'event: message\n'
      'data: {"choices":[{"delta":\n'
      'data: {"content":"你"}}]}\n\n'
      'data: [DONE]\n\n',
    );
    final events = await sseDataEvents(
      Stream<List<int>>.value(payload),
    ).toList();

    expect(events, hasLength(1));
    expect(events.single, contains('"content":"你"'));
  });

  test('maps Dio cancellation to the stable cancelled code', () {
    final mapped = mapProviderError(
      DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        type: DioExceptionType.cancel,
      ),
    );
    expect(mapped.code, AgentToolErrorCode.toolCancelled);
  });
}
