import 'package:dio/dio.dart';

import '../../../core/models/agent/agent_provider.dart';
import '../ports/llm_port.dart';
import '../ports/secret_port.dart';
import 'anthropic_provider.dart';
import 'openai_compatible_provider.dart';

LlmPort createLlmProvider({
  required AgentProviderConfig config,
  required SecretPort secrets,
  Dio? dio,
}) {
  return switch (config.kind) {
    AgentProviderKind.openAiCompatible => OpenAiCompatibleProvider(
      config: config,
      secrets: secrets,
      dio: dio,
    ),
    AgentProviderKind.anthropic => AnthropicProvider(
      config: config,
      secrets: secrets,
      dio: dio,
    ),
  };
}
