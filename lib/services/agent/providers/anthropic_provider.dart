import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/agent/agent_provider.dart';
import '../../../core/models/agent/agent_tool.dart';
import '../../security/secret_store.dart';
import '../ports/agent_capability_exception.dart';
import '../ports/llm_port.dart';
import '../ports/secret_port.dart';
import 'provider_http.dart';
import 'provider_payload.dart';

class AnthropicProvider implements LlmPort {
  AnthropicProvider({required this.config, required this.secrets, Dio? dio})
    : _dio = dio ?? Dio();

  final AgentProviderConfig config;
  final SecretPort secrets;
  final Dio _dio;

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    final cancelToken = CancelToken();
    void cancelRequest() => cancelToken.cancel('cancelled');
    cancellation?.addListener(cancelRequest);
    try {
      yield* _stream(request, cancellation, cancelToken);
    } finally {
      cancellation?.removeListener(cancelRequest);
    }
  }

  Stream<LlmEvent> _stream(
    LlmRequest request,
    LlmCancelToken? cancellation,
    CancelToken cancelToken,
  ) async* {
    if (cancellation?.isCancelled == true) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.toolCancelled,
        '已取消',
      );
    }
    final key = await secrets.read(agentProviderSecretKey(config.id));
    if (key == null || key.trim().isEmpty) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.notConfigured,
        '尚未配置 API Key',
      );
    }
    final watch = Stopwatch()..start();
    final useStream = request.stream && config.supportsStreaming;
    final payload = _payload(request, useStream);
    assertNoImagePayload(payload);
    final timeout = Duration(seconds: config.timeoutSeconds);
    final options = Options(
      headers: <String, String>{
        'x-api-key': key,
        'anthropic-version': '2026-10-21',
        'Content-Type': 'application/json',
      },
      responseType: useStream ? ResponseType.stream : ResponseType.json,
      sendTimeout: timeout,
      receiveTimeout: timeout,
    );

    try {
      final response = await postProviderRequest(
        _dio,
        '${config.normalizedBaseUrl}/v1/messages',
        data: payload,
        options: options,
        cancelToken: cancelToken,
        onAttempt: request.onHttpAttempt,
      );
      if (!useStream) {
        for (final event in _eventsFromResponse(response.data)) {
          yield event;
        }
        debugPrint(
          '[AgentTiming] provider anthropic non_stream '
          'elapsed=${watch.elapsedMilliseconds}ms',
        );
        return;
      }
      final body = response.data;
      if (body is! ResponseBody) {
        throw const AgentCapabilityException(
          AgentToolErrorCode.internalError,
          '模型服务返回格式异常',
        );
      }
      var firstEventAt = -1;
      var stopSeenAt = -1;
      await for (final data in sseDataEvents(body.stream)) {
        if (cancellation?.isCancelled == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        if (firstEventAt < 0) firstEventAt = watch.elapsedMilliseconds;
        final json = decodeJsonObject(data);
        final type = json['type'];
        if (type == 'content_block_delta') {
          final delta = json['delta'];
          if (delta is Map) {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              yield LlmEvent(type: LlmEventType.textDelta, text: text);
            }
          }
        } else if (type == 'error') {
          throw const AgentCapabilityException(
            AgentToolErrorCode.providerUnavailable,
            '模型服务返回错误',
          );
        } else if (type == 'message_stop') {
          // `message_stop` is the terminal SSE event. Return immediately so a
          // keep-alive socket cannot delay parsing/validation/rendering.
          stopSeenAt = watch.elapsedMilliseconds;
          debugPrint(
            '[AgentTiming] provider anthropic stream_closed '
            'elapsed=${watch.elapsedMilliseconds}ms '
            'first_event=${firstEventAt}ms stop_seen=$stopSeenAt',
          );
          yield LlmEvent.done();
          return;
        }
      }
      debugPrint(
        '[AgentTiming] provider anthropic stream_closed '
        'elapsed=${watch.elapsedMilliseconds}ms '
        'first_event=${firstEventAt}ms stop_seen=$stopSeenAt',
      );
    } catch (error) {
      debugPrint(
        '[AgentProvider] Anthropic error ${error.runtimeType}: '
        '${providerErrorDetail(error)}',
      );
      if (error is DioException && error.response?.statusCode == 400) {
        debugPrint(
          '[AgentProvider] Anthropic 400 request shape: '
          '${providerRequestShape(payload)}',
        );
      }
      throw mapProviderError(error, fallbackMessage: '模型服务请求失败');
    }
  }

  Iterable<LlmEvent> _eventsFromResponse(Object? data) sync* {
    final json = data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : decodeJsonObject(jsonEncode(data));
    final content = json['content'];
    if (content is List) {
      for (final block in content.whereType<Map>()) {
        final type = block['type'];
        if (type == 'text') {
          final text = block['text'];
          if (text is String && text.isNotEmpty) {
            yield LlmEvent(type: LlmEventType.textDelta, text: text);
          }
        }
      }
    }
    yield LlmEvent.done();
  }

  Map<String, Object?> _payload(LlmRequest request, bool stream) {
    final system = <String>[];
    final messages = <Map<String, Object?>>[];
    for (final message in validatedProviderMessages(request)) {
      if (message.role == LlmRole.system) {
        system.add(message.text.trim());
        continue;
      }
      final role = message.role == LlmRole.assistant ? 'assistant' : 'user';
      // Anthropic requires alternating roles. Merge accidental consecutive
      // messages of the same role instead of letting the API reject them.
      if (messages.isNotEmpty && messages.last['role'] == role) {
        final content = messages.last['content'] as List<Map<String, Object?>>;
        content.add(<String, Object?>{'type': 'text', 'text': message.text});
        continue;
      }
      messages.add(<String, Object?>{
        'role': role,
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': message.text},
        ],
      });
    }
    if (messages.isEmpty) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.invalidArguments,
        '请求缺少用户消息',
      );
    }
    final payload = <String, Object?>{
      'model': request.model.trim(),
      'max_tokens': config.maxOutputTokens > 0
          ? config.maxOutputTokens
          : validatedProviderMaxTokens(request),
      'messages': messages,
      'stream': stream,
    };
    if (system.isNotEmpty) payload['system'] = system.join('\n\n');
    return payload;
  }
}
