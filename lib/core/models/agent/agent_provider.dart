import 'agent_json.dart';

/// Validates a provider Base URL. The app manifest disables cleartext traffic,
/// so an HTTP endpoint would fail at runtime; reject it in the settings UI too.
String? agentBaseUrlError(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '请输入 Base URL';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return '请输入有效的 Base URL';
  if (uri.scheme != 'https') return 'Base URL 必须使用 HTTPS';
  if (uri.userInfo.isNotEmpty) return 'Base URL 不能包含账号或密码';
  return null;
}

enum AgentProviderKind {
  openAiCompatible('openai_compatible'),
  anthropic('anthropic');

  const AgentProviderKind(this.wireName);

  final String wireName;

  static AgentProviderKind fromWire(Object? value) {
    return value == AgentProviderKind.anthropic.wireName
        ? AgentProviderKind.anthropic
        : AgentProviderKind.openAiCompatible;
  }
}

/// User-facing service presets. These are UI presets, not persisted protocol
/// values: DeepSeek uses the OpenAI-compatible adapter; only [kind] is stored.
enum AgentProviderPreset {
  deepSeek(
    'DeepSeek',
    AgentProviderKind.openAiCompatible,
    'https://api.deepseek.com/',
  ),
  anthropic(
    'Claude（Anthropic）',
    AgentProviderKind.anthropic,
    'https://api.anthropic.com/',
  ),
  custom('其他 OpenAI 兼容服务', AgentProviderKind.openAiCompatible, '');

  const AgentProviderPreset(this.label, this.kind, this.defaultBaseUrl);

  final String label;
  final AgentProviderKind kind;
  final String defaultBaseUrl;

  static AgentProviderPreset forConfig(AgentProviderConfig? config) {
    if (config == null) return AgentProviderPreset.deepSeek;
    if (config.kind == AgentProviderKind.anthropic) {
      return AgentProviderPreset.anthropic;
    }
    if (config.normalizedBaseUrl ==
        _withoutTrailingSlash(AgentProviderPreset.deepSeek.defaultBaseUrl)) {
      return AgentProviderPreset.deepSeek;
    }
    return AgentProviderPreset.custom;
  }

  static String _withoutTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

/// Provider configuration without the API key. The key lives in SecretStore.
class AgentProviderConfig {
  const AgentProviderConfig({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.baseUrl,
    required this.smallModel,
    required this.complexModel,
    this.timeoutSeconds = 180,
    this.supportsJsonSchema = false,
    this.supportsStreaming = true,
  });

  final String id;
  final AgentProviderKind kind;
  final String displayName;
  final String baseUrl;
  final String smallModel;
  final String complexModel;
  final int timeoutSeconds;
  final bool supportsJsonSchema;
  final bool supportsStreaming;

  String get normalizedBaseUrl {
    var value = baseUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  AgentProviderConfig copyWith({
    String? id,
    AgentProviderKind? kind,
    String? displayName,
    String? baseUrl,
    String? smallModel,
    String? complexModel,
    int? timeoutSeconds,
    bool? supportsJsonSchema,
    bool? supportsStreaming,
  }) {
    return AgentProviderConfig(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      smallModel: smallModel ?? this.smallModel,
      complexModel: complexModel ?? this.complexModel,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      supportsJsonSchema: supportsJsonSchema ?? this.supportsJsonSchema,
      supportsStreaming: supportsStreaming ?? this.supportsStreaming,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.wireName,
    'display_name': displayName,
    'base_url': baseUrl,
    'small_model': smallModel,
    'complex_model': complexModel,
    'timeout_seconds': timeoutSeconds,
    'capabilities': {
      'json_schema': supportsJsonSchema,
      'streaming': supportsStreaming,
    },
  };

  factory AgentProviderConfig.fromJson(Map<String, Object?> json) {
    final capabilities = agentMap(json['capabilities']);
    return AgentProviderConfig(
      id: agentString(json['id']),
      kind: AgentProviderKind.fromWire(json['kind']),
      displayName: agentString(json['display_name']),
      baseUrl: agentString(json['base_url']),
      smallModel: agentString(json['small_model']),
      complexModel: agentString(json['complex_model']),
      timeoutSeconds: agentInt(json['timeout_seconds'], 180),
      supportsJsonSchema: agentBool(capabilities['json_schema']),
      supportsStreaming: agentBool(capabilities['streaming'], true),
    );
  }
}
