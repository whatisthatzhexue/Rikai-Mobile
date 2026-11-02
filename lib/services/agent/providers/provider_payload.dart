import 'package:flutter/foundation.dart';

import '../../../core/models/agent/agent_tool.dart';
import '../ports/agent_capability_exception.dart';
import '../ports/llm_port.dart';

/// Drops whitespace-only messages and rejects requests that could never be
/// valid at the provider. Anthropic rejects an empty `messages` array or empty
/// text content blocks; OpenAI-compatible services commonly reject empty
/// content too. This runs before any network call so the app fails with a
/// stable local error instead of an opaque HTTP 400.
List<LlmMessage> validatedProviderMessages(LlmRequest request) {
  if (request.model.trim().isEmpty) {
    throw const AgentCapabilityException(
      AgentToolErrorCode.invalidArguments,
      '模型名称不能为空',
    );
  }
  final messages = <LlmMessage>[];
  var droppedEmpty = 0;
  for (final message in request.messages) {
    final sanitized = sanitizeProviderTextWithStats(message.text);
    if (sanitized.hasChanges && kDebugMode) {
      debugPrint(
        '[AgentProvider] sanitized message text chars=${message.text.length} '
        'unpairedSurrogates=${sanitized.unpairedSurrogates} '
        'controlCharacters=${sanitized.controlCharacters}',
      );
    }
    if (sanitized.text.trim().isEmpty) {
      droppedEmpty++;
      continue;
    }
    messages.add(
      LlmMessage(
        role: message.role,
        parts: <LlmTextPart>[LlmTextPart(sanitized.text)],
      ),
    );
  }
  if (droppedEmpty > 0 && kDebugMode) {
    debugPrint('[AgentProvider] dropped empty messages=$droppedEmpty');
  }
  if (messages.isEmpty) {
    throw const AgentCapabilityException(
      AgentToolErrorCode.invalidArguments,
      '请求缺少有效消息',
    );
  }
  if (!messages.any((message) => message.role != LlmRole.system)) {
    throw const AgentCapabilityException(
      AgentToolErrorCode.invalidArguments,
      '请求缺少用户消息',
    );
  }
  return messages;
}

/// Never sends zero or a negative `max_tokens`; the actual upper limit is a
/// model/provider capability, so the app must not guess a universal ceiling.
/// A 400 is diagnosed from the provider's error body instead.
int validatedProviderMaxTokens(LlmRequest request) {
  if (request.maxTokens <= 0) {
    throw const AgentCapabilityException(
      AgentToolErrorCode.invalidArguments,
      'max_tokens 必须为正整数',
    );
  }
  return request.maxTokens;
}

class ProviderTextSanitization {
  const ProviderTextSanitization({
    required this.text,
    this.unpairedSurrogates = 0,
    this.controlCharacters = 0,
  });

  final String text;
  final int unpairedSurrogates;
  final int controlCharacters;

  bool get hasChanges => unpairedSurrogates > 0 || controlCharacters > 0;
}

/// Removes unpaired UTF-16 surrogates and C0 control characters that can make
/// a provider reject an otherwise well-formed JSON body (for example OCR
/// garbage). Newlines (`\n`), tabs (`\t`) and carriage returns (`\r`) are
/// preserved so normal multi-line prompts keep their meaning.
ProviderTextSanitization sanitizeProviderTextWithStats(String input) {
  final buffer = StringBuffer();
  var unpairedSurrogates = 0;
  var controlCharacters = 0;
  for (var index = 0; index < input.length; index++) {
    final unit = input.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 < input.length) {
        final next = input.codeUnitAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          buffer.writeCharCode(unit);
          buffer.writeCharCode(next);
          index++;
          continue;
        }
      }
      unpairedSurrogates++;
      buffer.writeCharCode(0xfffd);
      continue;
    }
    if (unit >= 0xdc00 && unit <= 0xdfff) {
      unpairedSurrogates++;
      buffer.writeCharCode(0xfffd);
      continue;
    }
    if (unit < 0x20 && unit != 0x09 && unit != 0x0a && unit != 0x0d) {
      controlCharacters++;
      buffer.writeCharCode(0x20);
      continue;
    }
    buffer.writeCharCode(unit);
  }
  return ProviderTextSanitization(
    text: buffer.toString(),
    unpairedSurrogates: unpairedSurrogates,
    controlCharacters: controlCharacters,
  );
}

String sanitizeProviderText(String input) =>
    sanitizeProviderTextWithStats(input).text;

const Set<String> _blockedKeyParts = <String>{
  'image_url',
  'input_image',
  'image_base64',
  'image_path',
  'image_file',
  'image_bytes',
  'base64',
  'file_path',
  'local_path',
  'content_uri',
};

const List<String> _blockedValueParts = <String>[
  'data:image',
  'base64,',
  'file://',
  'content://',
  '/sdcard/',
  'Android/data',
  '/storage/emulated',
  'C:\\',
  'c:\\',
];

/// Compile-time text-only DTOs are not enough; this runtime guard catches
/// accidental image/path leakage before a provider request leaves the device.
void assertNoImagePayload(Object? value, [String path = r'$']) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      for (final blocked in _blockedKeyParts) {
        if (key == blocked || key.contains(blocked)) {
          throw AgentCapabilityException(
            AgentToolErrorCode.invalidArguments,
            '请求包含不允许的图片或文件字段',
          );
        }
      }
      assertNoImagePayload(entry.value, '$path.${entry.key}');
    }
    return;
  }
  if (value is List) {
    for (var index = 0; index < value.length; index++) {
      assertNoImagePayload(value[index], '$path[$index]');
    }
    return;
  }
  if (value is String) {
    final lower = value.toLowerCase();
    for (final blocked in _blockedValueParts) {
      if (lower.contains(blocked)) {
        throw AgentCapabilityException(
          AgentToolErrorCode.invalidArguments,
          '请求包含不允许的图片或本地路径',
        );
      }
    }
  }
}
