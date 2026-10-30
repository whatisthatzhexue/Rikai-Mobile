import '../../../core/models/agent/agent_tool.dart';

/// A stable, user-safe failure raised by an Agent capability port.
class AgentCapabilityException implements Exception {
  const AgentCapabilityException(this.code, this.message, {this.cause});

  final AgentToolErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AgentCapabilityException(${code.wireName}): $message';
}
