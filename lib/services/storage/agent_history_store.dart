import '../../core/models/agent/agent_history.dart';
import '../../core/models/agent/agent_input.dart';
import '../agent/agent_run.dart';

/// A persisted history detail: metadata plus the validated structured result.
///
/// [result] is null for an error/cancel/interrupted run that never produced a
/// retained result. [unsupportedFormat] means a result row existed but its
/// schema could not be read; the UI must show a read-only notice instead of
/// guessing.
class AgentHistoryDetail {
  const AgentHistoryDetail({
    required this.entry,
    required this.userText,
    this.result,
    this.unsupportedFormat = false,
  });

  final AgentHistoryEntry entry;
  final String userText;
  final AgentRunResult? result;
  final bool unsupportedFormat;
}

/// Persistence seam for one-run history. Implemented by `AgentStore`.
abstract interface class AgentHistoryRepository {
  /// Marks runs left in an in-flight state by a previous process as
  /// `interrupted`. Returns the number of rows updated.
  Future<int> markInterruptedRuns();

  /// Upserts one run. A non-null [result] replaces the saved result and the
  /// derived source/citation rows; a null result leaves any previously saved
  /// result untouched.
  Future<void> saveHistoryRun({
    required String runId,
    required String sessionId,
    required String title,
    required String userText,
    required String status,
    required AgentMode mode,
    required String providerLabel,
    required String smallModel,
    required String complexModel,
    required int imageCount,
    required DateTime startedAt,
    DateTime? finishedAt,
    AgentRunResult? result,
    String errorCode = '',
  });

  Future<List<AgentHistoryEntry>> listHistory();

  Future<AgentHistoryDetail?> loadHistoryDetail(String runId);

  Future<void> deleteHistoryRun(String runId);

  /// Deletes several runs in one transaction. Missing ids are ignored.
  Future<void> deleteHistoryRuns(Iterable<String> runIds);

  Future<void> clearHistory();
}
