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

class OpenAiCompatibleProvider implements LlmPort {
  OpenAiCompatibleProvider({
    required this.config,
    required this.secrets,
    Dio? dio,
  }) : _dio = dio ?? Dio();

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
    final useStream = request.stream && config.supportsStreaming;
    final payload = _payload(request, useStream);
    assertNoImagePayload(payload);
    final timeout = Duration(seconds: config.timeoutSeconds);
    final options = Options(
      headers: <String, String>{
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
      responseType: useStream ? ResponseType.stream : ResponseType.json,
      sendTimeout: timeout,
      receiveTimeout: timeout,
    );

    try {
      final response = await postProviderRequest(
        _dio,
        '${config.normalizedBaseUrl}/chat/completions',
        data: payload,
        options: options,
        cancelToken: cancelToken,
      );
      if (!useStream) {
        for (final event in _eventsFromResponse(response.data)) {
          yield event;
        }
        return;
      }
      final body = response.data;
      if (body is! ResponseBody) {
        throw const AgentCapabilityException(
          AgentToolErrorCode.internalError,
          '模型服务返回格式异常',
        );
      }
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      debugPrint(
        '[AgentProvider] HTTP ${response.statusCode} '
        'content-type=$contentType',
      );
      if (!contentType.contains('text/event-stream')) {
        final bytes = await body.stream.fold<List<int>>(
          <int>[],
          (buffer, chunk) => buffer..addAll(chunk),
        );
        final text = utf8.decode(bytes);
        if (text.trimLeft().startsWith('data:')) {
          for (final line in const LineSplitter().convert(text)) {
            if (!line.startsWith('data:')) continue;
            final data = line.substring(5).trim();
            if (data.isEmpty || data == '[DONE]') continue;
            for (final event in _eventsFromResponse(decodeJsonObject(data))) {
              yield event;
            }
          }
          return;
        }
        for (final event in _eventsFromResponse(decodeJsonObject(text))) {
          yield event;
        }
        return;
      }

      var sseEvents = 0;
      var textChars = 0;
      var reasoningChars = 0;
      var lastFinishReason = '';
      await for (final data in sseDataEvents(body.stream)) {
        if (cancellation?.isCancelled == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        sseEvents++;
        final Map<String, Object?> json;
        try {
          json = decodeJsonObject(data);
        } catch (error) {
          debugPrint(
            '[AgentProvider] SSE JSON decode failed '
            '(${error.runtimeType}, chars=${data.length})',
          );
          continue;
        }
        if (json['error'] != null) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.providerUnavailable,
            '模型服务返回错误',
          );
        }
        final choices = json['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map) continue;
        final finishReason = choice['finish_reason'];
        if (finishReason is String && finishReason.isNotEmpty) {
          lastFinishReason = finishReason;
        }
        final delta = choice['delta'];
        if (delta is Map) {
          final reasoning = delta['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            reasoningChars += reasoning.length;
            yield LlmEvent(type: LlmEventType.reasoningDelta, text: reasoning);
          }
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            textChars += content.length;
            yield LlmEvent(type: LlmEventType.textDelta, text: content);
          }
        }
      }
      debugPrint(
        '[AgentProvider] SSE events=$sseEvents textChars=$textChars '
        'reasoningChars=$reasoningChars finish=$lastFinishReason',
      );
      if (textChars == 0) {
        if (reasoningChars > 0) {
          // Some reasoning models spend the entire output budget on
          // reasoning_content and never emit content. Repeating the same
          // expensive request non-streaming only doubles latency.
          debugPrint(
            '[AgentProvider] reasoning-only stream with no content; '
            'not retrying',
          );
          throw const AgentCapabilityException(
            AgentToolErrorCode.providerEmptyOutput,
            '模型只返回了思考内容，没有生成正文；请改用非推理模型或调整模型输出上限',
          );
        }
        debugPrint(
          '[AgentProvider] empty stream; falling back to non-streaming',
        );
        final fallback = await postProviderRequest(
          _dio,
          '${config.normalizedBaseUrl}/chat/completions',
          data: <String, Object?>{...payload, 'stream': false},
          options: Options(
            headers: options.headers,
            responseType: ResponseType.json,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
          cancelToken: cancelToken,
        );
        for (final event in _eventsFromResponse(fallback.data)) {
          yield event;
        }
        return;
      }
      yield LlmEvent.done();
    } catch (error) {
      debugPrint(
        '[AgentProvider] OpenAI-compatible error '
        '${error.runtimeType}: ${providerErrorDetail(error)}',
      );
      if (error is DioException && error.response?.statusCode == 400) {
        debugPrint(
          '[AgentProvider] OpenAI-compatible 400 request shape: '
          '${providerRequestShape(payload)}',
        );
      }
      throw mapProviderError(error, fallbackMessage: '模型服务请求失败');
    }
  }

  Iterable<LlmEvent> _eventsFromResponse(Object? data) sync* {
    final Map<String, Object?> json;
    if (data is Map) {
      json = data.map((key, value) => MapEntry(key.toString(), value));
    } else if (data is String) {
      json = decodeJsonObject(data);
    } else {
      debugPrint(
        '[AgentProvider] non-map/non-string provider response: '
        '${data.runtimeType}',
      );
      json = decodeJsonObject(jsonEncode(data));
    }
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map) {
        final reasoning = message['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) {
          yield LlmEvent(type: LlmEventType.reasoningDelta, text: reasoning);
        }
        final text = openAiTextContent(message['content']);
        if (text != null && text.isNotEmpty) {
          yield LlmEvent(type: LlmEventType.textDelta, text: text);
        }
      }
    }
    yield LlmEvent.done();
  }

  Map<String, Object?> _payload(LlmRequest request, bool stream) {
    // Validate the local budget contract, but do not send max_tokens to an
    // OpenAI-compatible endpoint. Providers/models disagree about whether
    // hidden reasoning counts against it; sending a fixed 12k budget made
    // reasoning models emit only reasoning_content and no final answer.
    validatedProviderMaxTokens(request);
    return <String, Object?>{
      'model': request.model.trim(),
      'messages': validatedProviderMessages(request)
          .map(
            (message) => <String, Object?>{
              'role': message.role.name,
              'content': message.text,
            },
          )
          .toList(),
      'stream': stream,
    };
  }
}
