import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/agent/agent_run.dart';
import '../services/storage/agent_history_store.dart';
import 'agent_providers.dart';
import 'agent_run_controller.dart';

/// Persistence seam for history. Tests can override this with an in-memory
/// repository without opening SQLite.
final agentHistoryRepositoryProvider = Provider<AgentHistoryRepository>((ref) {
  return ref.watch(agentStoreProvider);
});

/// App-scoped recorder. It is started once from app bootstrap and listens to
/// the application-level run controller, so leaving the Agent page does not
/// interrupt history writes.
final agentHistoryRecorderProvider = Provider<AgentHistoryRecorder>((ref) {
  final recorder = AgentHistoryRecorder(
    ref.watch(agentHistoryRepositoryProvider),
  );
  ref.onDispose(recorder.dispose);
  ref.listen(agentRunControllerProvider, recorder.onStateChanged);
  unawaited(recorder.start());
  return recorder;
});

class AgentHistoryRecorder {
  AgentHistoryRecorder(this._repository);

  final AgentHistoryRepository _repository;
  String? _lastRunId;
  String? _lastStatus;
  AgentRunResult? _lastResult;
  AgentRunResult? _lastProvisional;

  Future<void> start() async {
    try {
      await _repository.markInterruptedRuns();
    } catch (error, stack) {
      debugPrint('[AgentHistory] markInterrupted failed: $error\n$stack');
    }
  }

  void dispose() {
    _lastRunId = null;
    _lastStatus = null;
    _lastResult = null;
    _lastProvisional = null;
  }

  void onStateChanged(AgentRunSnapshot? previous, AgentRunSnapshot next) {
    final runId = next.runId;
    if (runId == null || next.status == AgentRunStatus.idle) {
      _lastRunId = null;
      _lastStatus = null;
      _lastResult = null;
      _lastProvisional = null;
      return;
    }

    final status = _wireStatus(next.status);
    final finalStatus = _isFinal(next.status);
    // A failed/cancelled regeneration may still carry an older retained result
    // for display. It belongs to the previous run, not to this history entry,
    // so only a result produced by this run is persisted.
    final result = switch (next.status) {
      AgentRunStatus.done => next.result ?? next.provisionalResult,
      AgentRunStatus.error ||
      AgentRunStatus.cancelled ||
      AgentRunStatus.interrupted => next.provisionalResult,
      _ => next.provisionalResult,
    };
    final provisional = next.provisionalResult;
    if (_lastRunId == runId &&
        _lastStatus == status &&
        identical(_lastResult, result) &&
        identical(_lastProvisional, provisional)) {
      return;
    }
    _lastRunId = runId;
    _lastStatus = status;
    _lastResult = result;
    _lastProvisional = provisional;
    unawaited(
      _repository
          .saveHistoryRun(
            runId: runId,
            sessionId: next.sessionId ?? 'session-$runId',
            title: _title(next),
            userText: next.sentText,
            status: status,
            mode: next.mode,
            providerLabel: next.providerLabel,
            smallModel: '',
            complexModel: '',
            imageCount: _imageCount(next),
            startedAt: next.startedAt ?? DateTime.now(),
            finishedAt: finalStatus ? next.finishedAt ?? DateTime.now() : null,
            result: result,
            errorCode: next.errorCode?.wireName ?? '',
          )
          .catchError((Object error, StackTrace stack) {
            debugPrint('[AgentHistory] save failed: $error\n$stack');
            if (_lastRunId == runId &&
                _lastStatus == status &&
                identical(_lastResult, result)) {
              // Force the next state notification to retry the write.
              _lastStatus = null;
            }
          }),
    );
  }

  static bool _isFinal(AgentRunStatus status) => switch (status) {
    AgentRunStatus.done ||
    AgentRunStatus.error ||
    AgentRunStatus.cancelled ||
    AgentRunStatus.interrupted => true,
    _ => false,
  };

  static String _wireStatus(AgentRunStatus status) => switch (status) {
    AgentRunStatus.preparing => 'preparing',
    AgentRunStatus.ocr => 'ocr',
    AgentRunStatus.familiarizing => 'familiarizing',
    AgentRunStatus.awaitingProfile => 'awaiting_profile',
    AgentRunStatus.tokenizing => 'tokenizing',
    AgentRunStatus.reasoning => 'reasoning',
    AgentRunStatus.validating => 'validating',
    AgentRunStatus.done => 'done',
    AgentRunStatus.error => 'error',
    AgentRunStatus.cancelled => 'cancelled',
    AgentRunStatus.interrupted => 'interrupted',
    AgentRunStatus.idle => 'idle',
  };

  static int _imageCount(AgentRunSnapshot snapshot) {
    if (snapshot.sentImagePaths.isNotEmpty) {
      return snapshot.sentImagePaths.length;
    }
    return snapshot.sentImage ? 1 : 0;
  }

  static String _title(AgentRunSnapshot snapshot) {
    final text = snapshot.sentText.trim();
    if (text.isNotEmpty) {
      final firstLine = text.split(RegExp(r'[\r\n]')).first.trim();
      if (firstLine.isNotEmpty) {
        return firstLine.length <= 80
            ? firstLine
            : '${firstLine.substring(0, 80)}…';
      }
    }
    return snapshot.sentImage ? '图片分析' : '分析';
  }
}
