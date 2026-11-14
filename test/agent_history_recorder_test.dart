import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_analysis.dart';
import 'package:lexicandy/core/models/agent/agent_evidence.dart';
import 'package:lexicandy/core/models/agent/agent_history.dart';
import 'package:lexicandy/core/models/agent/agent_input.dart';
import 'package:lexicandy/core/models/agent/agent_quote.dart';
import 'package:lexicandy/services/agent/agent_run.dart';
import 'package:lexicandy/services/agent/agent_validator.dart';
import 'package:lexicandy/services/storage/agent_history_store.dart';
import 'package:lexicandy/state/agent_history_recorder.dart';

AgentRunResult _emptyResult() {
  return const AgentRunResult(
    input: AgentInputEnvelope(
      sessionId: 'session-1',
      mode: AgentMode.strict,
      sources: <AgentSourceInput>[],
    ),
    evidence: AgentEvidenceBundle(sources: <AgentSourceEvidence>[]),
    quotes: <AgentQuoteRef>[],
    analysis: AgentAnalysis(sourceId: 'src-1'),
    validation: AgentValidationResult(
      valid: true,
      errors: <String>[],
      citationsUsed: <String>[],
    ),
    sources: <AgentSourceVersion>[],
    dictionaryProfiles: <String>[],
  );
}

AgentRunSnapshot _snapshot({
  required String runId,
  required AgentRunStatus status,
  String sentText = '',
  List<String> imagePaths = const <String>[],
  AgentRunResult? result,
  AgentRunResult? provisionalResult,
  DateTime? startedAt,
  DateTime? finishedAt,
}) {
  return AgentRunSnapshot(
    runId: runId,
    sessionId: 'session-1',
    status: status,
    sentText: sentText,
    sentImage: imagePaths.isNotEmpty,
    sentImagePaths: imagePaths,
    mode: AgentMode.strict,
    providerLabel: 'DeepSeek',
    startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
    finishedAt: finishedAt,
    result: result,
    provisionalResult: provisionalResult,
  );
}

class _FakeHistoryRepository implements AgentHistoryRepository {
  bool marked = false;
  final List<Map<String, Object?>> saves = <Map<String, Object?>>[];

  @override
  Future<int> markInterruptedRuns() async {
    marked = true;
    return 1;
  }

  @override
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
  }) async {
    saves.add(<String, Object?>{
      'runId': runId,
      'sessionId': sessionId,
      'title': title,
      'userText': userText,
      'status': status,
      'mode': mode,
      'providerLabel': providerLabel,
      'imageCount': imageCount,
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      'result': result,
      'errorCode': errorCode,
    });
  }

  @override
  Future<List<AgentHistoryEntry>> listHistory() async =>
      const <AgentHistoryEntry>[];

  @override
  Future<AgentHistoryDetail?> loadHistoryDetail(String runId) async => null;

  @override
  Future<void> deleteHistoryRun(String runId) async {}

  @override
  Future<void> deleteHistoryRuns(Iterable<String> runIds) async {}

  @override
  Future<void> clearHistory() async {}
}

void main() {
  test('provider starts the recorder and marks interrupted runs', () async {
    final repository = _FakeHistoryRepository();
    final container = ProviderContainer(
      overrides: [agentHistoryRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(agentHistoryRecorderProvider);
    await pumpEventQueue();
    expect(repository.marked, isTrue);
  });

  test('records start, provisional, done and skips duplicate states', () async {
    final repository = _FakeHistoryRepository();
    final recorder = AgentHistoryRecorder(repository);
    await recorder.start();
    expect(repository.marked, isTrue);

    final started = DateTime.fromMillisecondsSinceEpoch(1000);
    final finished = DateTime.fromMillisecondsSinceEpoch(2000);
    final result = _emptyResult();

    recorder.onStateChanged(
      null,
      _snapshot(
        runId: 'run-1',
        status: AgentRunStatus.preparing,
        sentText: '何卒\n二行目',
        imagePaths: const <String>['/private/a.jpg', '/private/b.jpg'],
        startedAt: started,
      ),
    );
    await pumpEventQueue();
    expect(repository.saves, hasLength(1));
    expect(repository.saves.single['status'], 'preparing');
    expect(repository.saves.single['title'], '何卒');
    expect(repository.saves.single['imageCount'], 2);
    expect(repository.saves.single['result'], isNull);
    expect(repository.saves.single.toString(), isNot(contains('/private/')));

    final provisionalSnapshot = _snapshot(
      runId: 'run-1',
      status: AgentRunStatus.validating,
      sentText: '何卒',
      result: null,
      provisionalResult: result,
      startedAt: started,
    );
    recorder.onStateChanged(null, provisionalSnapshot);
    await pumpEventQueue();
    expect(repository.saves, hasLength(2));
    expect(repository.saves.last['status'], 'validating');
    expect(repository.saves.last['result'], same(result));

    final doneSnapshot = _snapshot(
      runId: 'run-1',
      status: AgentRunStatus.done,
      sentText: '何卒',
      result: result,
      startedAt: started,
      finishedAt: finished,
    );
    recorder.onStateChanged(provisionalSnapshot, doneSnapshot);
    await pumpEventQueue();
    expect(repository.saves, hasLength(3));
    expect(repository.saves.last['status'], 'done');
    expect(repository.saves.last['finishedAt'], finished);
    expect(repository.saves.last['result'], same(result));

    // Duplicate progress/done notifications do not write again.
    recorder.onStateChanged(doneSnapshot, doneSnapshot);
    await pumpEventQueue();
    expect(repository.saves, hasLength(3));
  });

  test('error with a provisional result keeps that result', () async {
    final repository = _FakeHistoryRepository();
    final recorder = AgentHistoryRecorder(repository);
    final result = _emptyResult();
    recorder.onStateChanged(
      null,
      _snapshot(
        runId: 'run-error',
        status: AgentRunStatus.error,
        sentText: '何卒',
        provisionalResult: result,
        finishedAt: DateTime.fromMillisecondsSinceEpoch(3000),
      ),
    );
    await pumpEventQueue();
    expect(repository.saves, hasLength(1));
    expect(repository.saves.single['status'], 'error');
    expect(repository.saves.single['result'], same(result));
  });
}
