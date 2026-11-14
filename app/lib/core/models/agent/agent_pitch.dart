import 'agent_json.dart';

/// One locally derived UniDic pitch accent.
///
/// This DTO never enters a provider request. [source] is deliberately fixed to
/// `unidic`; there is no AI-guessed variant.
class AgentPitchAccent {
  const AgentPitchAccent({
    required this.accentType,
    required this.moraCount,
    required this.moraPattern,
  });

  static const String schema = 'rikai.agent.pitch.v1';
  static const String source = 'unidic';

  /// UniDic `aType`: 0=flat, 1=initial-high, N=drop after mora N.
  final int accentType;
  final int moraCount;

  /// `L`/`H` per mora, length [moraCount].
  final String moraPattern;

  bool get isValid =>
      accentType >= 0 &&
      moraCount >= 2 &&
      accentType <= moraCount &&
      moraPattern.length == moraCount &&
      RegExp(r'^[LH]+$').hasMatch(moraPattern);

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'source': source,
    'accent_type': accentType,
    'mora_count': moraCount,
    'mora_pattern': moraPattern,
  };

  factory AgentPitchAccent.fromJson(Map<String, Object?> json) {
    return AgentPitchAccent(
      accentType: agentInt(json['accent_type']),
      moraCount: agentInt(json['mora_count']),
      moraPattern: agentString(json['mora_pattern']),
    );
  }
}
