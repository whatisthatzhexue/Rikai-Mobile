import 'agent_input.dart';
import 'agent_json.dart';

/// One finalised Agent run shown in the assistant history.
///
/// This DTO deliberately has no image path/thumbnail/base64 field. Images are
/// never persisted by the Agent store; [imageCount] is display metadata only.
enum AgentHistoryStatus {
  done('done'),
  error('error'),
  cancelled('cancelled'),
  interrupted('interrupted');

  const AgentHistoryStatus(this.wireName);

  final String wireName;

  static AgentHistoryStatus fromWire(Object? value) {
    for (final status in AgentHistoryStatus.values) {
      if (status.wireName == value) return status;
    }
    return AgentHistoryStatus.error;
  }
}

class AgentHistoryEntry {
  const AgentHistoryEntry({
    required this.runId,
    required this.sessionId,
    required this.title,
    required this.status,
    required this.mode,
    required this.startedAt,
    this.finishedAt,
    this.providerLabel = '',
    this.smallModel = '',
    this.complexModel = '',
    this.imageCount = 0,
    this.hasResult = false,
    this.errorCode = '',
  });

  static const String schema = 'rikai.agent.history-entry.v1';

  final String runId;
  final String sessionId;
  final String title;
  final AgentHistoryStatus status;
  final AgentMode mode;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String providerLabel;
  final String smallModel;
  final String complexModel;
  final int imageCount;
  final bool hasResult;
  final String errorCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'run_id': runId,
    'session_id': sessionId,
    'title': title,
    'status': status.wireName,
    'mode': mode.wireName,
    'started_at': startedAt.millisecondsSinceEpoch,
    if (finishedAt != null) 'finished_at': finishedAt!.millisecondsSinceEpoch,
    if (providerLabel.isNotEmpty) 'provider_label': providerLabel,
    if (smallModel.isNotEmpty) 'small_model': smallModel,
    if (complexModel.isNotEmpty) 'complex_model': complexModel,
    'image_count': imageCount,
    'has_result': hasResult,
    if (errorCode.isNotEmpty) 'error_code': errorCode,
  };

  factory AgentHistoryEntry.fromJson(Map<String, Object?> json) {
    final rawFinished = json['finished_at'];
    final finishedAt = rawFinished is num
        ? DateTime.fromMillisecondsSinceEpoch(rawFinished.toInt())
        : null;
    return AgentHistoryEntry(
      runId: agentString(json['run_id']),
      sessionId: agentString(json['session_id']),
      title: agentString(json['title']),
      status: AgentHistoryStatus.fromWire(json['status']),
      mode: AgentMode.fromWire(json['mode']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        agentInt(json['started_at']),
      ),
      finishedAt: finishedAt,
      providerLabel: agentString(json['provider_label']),
      smallModel: agentString(json['small_model']),
      complexModel: agentString(json['complex_model']),
      imageCount: agentInt(json['image_count']),
      hasResult: agentBool(json['has_result']),
      errorCode: agentString(json['error_code']),
    );
  }
}
