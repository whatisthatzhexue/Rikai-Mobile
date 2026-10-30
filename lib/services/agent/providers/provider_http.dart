import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/agent/agent_tool.dart';
import '../ports/agent_capability_exception.dart';

/// Yields one payload per SSE event. A single event may span multiple `data:`
/// lines (joined with `\n`), which some providers use for long JSON payloads.
Stream<String> sseDataEvents(Stream<List<int>> bytes) async* {
  // Dio exposes Stream<Uint8List>; utf8.decoder is a
  // StreamTransformer<List<int>, String>, so cast the stream first or Dart's
  // invariant generics fail at runtime.
  final lines = utf8.decoder
      .bind(bytes.cast<List<int>>())
      .transform(const LineSplitter());
  final data = <String>[];
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isEmpty) continue;
      final payload = data.join('\n');
      data.clear();
      if (payload.trim().isEmpty || payload.trim() == '[DONE]') continue;
      yield payload;
      continue;
    }
    if (!line.startsWith('data:')) continue;
    data.add(line.substring(5).trimLeft());
  }
  if (data.isNotEmpty) {
    final payload = data.join('\n');
    if (payload.trim().isNotEmpty && payload.trim() != '[DONE]') yield payload;
  }
}

bool isRetryableProviderError(DioException error) {
  if (error.type == DioExceptionType.cancel) return false;
  final status = error.response?.statusCode;
  if (status != null) return status == 429 || status >= 500;
  return error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.connectionError;
}

/// Retries the initial request for 429/5xx/timeouts. Streaming bodies are not
/// retried after any event was yielded, so a repair/analysis attempt never
/// duplicates model output.
Future<Response<Object?>> postProviderRequest(
  Dio dio,
  String url, {
  required Object? data,
  required Options options,
  CancelToken? cancelToken,
  int maxAttempts = 3,
}) async {
  var delay = const Duration(milliseconds: 400);
  DioException? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await dio.post<Object?>(
        url,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      lastError = error;
      if (!isRetryableProviderError(error) ||
          attempt == maxAttempts ||
          (cancelToken?.isCancelled ?? false)) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '[AgentProvider] retrying after ${error.type} '
          '(status=${error.response?.statusCode}, attempt=$attempt)',
        );
      }
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
  throw lastError!;
}

Map<String, Object?> decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('provider response is not an object');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

String? openAiTextContent(Object? content) {
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map) {
        final text = part['text'];
        if (text is String) buffer.write(text);
      }
    }
    return buffer.toString();
  }
  return null;
}

AgentCapabilityException mapProviderError(
  Object error, {
  String fallbackMessage = '模型服务请求失败',
}) {
  if (error is AgentCapabilityException) return error;
  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) {
      return const AgentCapabilityException(
        AgentToolErrorCode.toolCancelled,
        '已取消',
      );
    }
    final status = error.response?.statusCode;
    final detail = _providerErrorMessage(error.response?.data);
    if (kDebugMode) {
      if (status != null) {
        debugPrint(
          '[AgentProvider] HTTP $status'
          '${detail.isEmpty ? '' : ': $detail'}',
        );
      } else {
        debugPrint('[AgentProvider] ${error.type} (${error.message})');
      }
    }
    if (status == 401 || status == 403) {
      return AgentCapabilityException(
        AgentToolErrorCode.providerAuthFailed,
        'API Key 无效或没有权限',
        cause: error,
      );
    }
    if (status == 429) {
      return AgentCapabilityException(
        AgentToolErrorCode.providerRateLimited,
        '模型服务限流，请稍后重试',
        cause: error,
      );
    }
    if (status != null && status >= 500) {
      return AgentCapabilityException(
        AgentToolErrorCode.providerUnavailable,
        '模型服务暂不可用',
        cause: error,
      );
    }
    if (status == 400 || status == 404 || status == 422) {
      return AgentCapabilityException(
        AgentToolErrorCode.invalidArguments,
        detail.isEmpty
            ? '模型请求被拒绝（HTTP $status），请检查模型名、Base URL 和参数'
            : '模型请求被拒绝（HTTP $status）：$detail',
        cause: error,
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return AgentCapabilityException(
        AgentToolErrorCode.toolTimeout,
        '模型服务响应超时',
        cause: error,
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return AgentCapabilityException(
        AgentToolErrorCode.providerUnavailable,
        '无法连接模型服务',
        cause: error,
      );
    }
  }
  if (error is TimeoutException) {
    return AgentCapabilityException(
      AgentToolErrorCode.toolTimeout,
      '模型服务响应超时',
      cause: error,
    );
  }
  return AgentCapabilityException(
    AgentToolErrorCode.internalError,
    fallbackMessage,
    cause: error,
  );
}

String providerErrorDetail(Object error) {
  var raw = error.toString();
  raw = raw
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[redacted]')
      .replaceAll(
        RegExp(r'(authorization|x-api-key)\s*[:=]\s*\S+', caseSensitive: false),
        '[redacted]',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (raw.length > 240) raw = '${raw.substring(0, 240)}…';
  return raw;
}

String _providerErrorMessage(Object? data) {
  String raw = '';
  if (data is Map) {
    final map = data.map((key, value) => MapEntry(key.toString(), value));
    final nested = map['error'];
    if (nested is Map) {
      raw = nested['message']?.toString() ?? nested['detail']?.toString() ?? '';
    }
    raw = raw.isNotEmpty
        ? raw
        : (map['message'] ?? map['detail'] ?? map['error'] ?? '').toString();
  } else if (data is String) {
    raw = data;
  } else if (data is ResponseBody) {
    return '';
  }
  raw = raw
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[redacted]')
      .replaceAll(
        RegExp(r'(authorization|x-api-key)\s*[:=]\s*\S+', caseSensitive: false),
        '[redacted]',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (raw.length > 300) raw = '${raw.substring(0, 300)}…';
  return raw;
}
