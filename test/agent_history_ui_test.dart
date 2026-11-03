import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_history.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_history_detail_page.dart';
import 'package:rikai_mobile/features/agent/agent_history_page.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/agent_validator.dart';
import 'package:rikai_mobile/services/storage/agent_history_store.dart';
import 'package:rikai_mobile/state/agent_history_recorder.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:rikai_ocr/rikai_ocr.dart';
import 'package:shared_preferences/shared_preferences.dart';

AgentRunResult _result() {
  const source = AgentSourceInput(
    id: 'src-1',
    kind: AgentSourceKind.imageOcr,
    imageId: 'img-1',
    selectedVariantId: 'var-1',
    variants: <AgentOcrVariant>[
      AgentOcrVariant(
        id: 'var-1',
        engine: 'paddle_v5',
        mode: OcrMode.auto,
        text: '何卒',
        confidence: 0.9,
      ),
      AgentOcrVariant(
        id: 'var-2',
        engine: 'manga_ocr',
        mode: OcrMode.vertical,
        text: '何卒',
        confidence: 0.8,
      ),
    ],
  );
  const quote = AgentQuoteRef(
    id: 'q1',
    sourceId: 'src-1',
    start: 0,
    end: 2,
    text: '何卒',
    origin: AgentQuoteOrigin.ocr,
  );
  const citation = AgentCitation(
    id: 'source-1',
    kind: 'mdict',
    dictionaryId: 'dict-1',
    dictionaryTitle: 'テスト辞典',
    dictionaryOrder: 0,
    entryKey: '何卒',
    matchedKey: '何卒',
    headword: '何卒',
    snippet: 'なにとぞ。どうか。',
    toolCallId: 'call-1',
  );
  return AgentRunResult(
    input: const AgentInputEnvelope(
      sessionId: 'session-1',
      mode: AgentMode.strict,
      userText: '何卒',
      sources: <AgentSourceInput>[source],
    ),
    evidence: const AgentEvidenceBundle(
      sources: <AgentSourceEvidence>[],
      citations: <AgentCitation>[citation],
    ),
    quotes: const <AgentQuoteRef>[quote],
    analysis: const AgentAnalysis(
      sourceId: 'src-1',
      translation: <AgentTranslation>[
        AgentTranslation(quoteId: 'q1', text: '请务必'),
      ],
      segments: <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          interpretation: '正式请求对方关照。',
          epistemic: AgentEpistemic.contextInference,
          confidence: 0.8,
        ),
      ],
    ),
    validation: const AgentValidationResult(
      valid: true,
      errors: <String>[],
      citationsUsed: <String>['source-1'],
    ),
    sources: const <AgentSourceVersion>[
      AgentSourceVersion(
        id: 'sv-1',
        sourceId: 'src-1',
        origin: AgentQuoteOrigin.ocr,
        text: '何卒',
        imageId: 'img-1',
        variantId: 'var-1',
        engine: 'paddle_v5',
        mode: 'auto',
        confidence: 0.9,
      ),
    ],
    dictionaryProfiles: const <String>[],
  );
}

AgentHistoryEntry _entry() => AgentHistoryEntry(
  runId: 'run-1',
  sessionId: 'session-1',
  title: '何卒宜しくお願い致します。',
  status: AgentHistoryStatus.done,
  mode: AgentMode.strict,
  startedAt: DateTime.now().subtract(const Duration(seconds: 2)),
  finishedAt: DateTime.now(),
  providerLabel: 'DeepSeek',
  imageCount: 1,
  hasResult: true,
);

class _MutableHistoryRepository implements AgentHistoryRepository {
  _MutableHistoryRepository(List<AgentHistoryEntry> entries)
    : _entries = List<AgentHistoryEntry>.of(entries);

  final List<AgentHistoryEntry> _entries;

  @override
  Future<void> clearHistory() async => _entries.clear();

  @override
  Future<void> deleteHistoryRun(String runId) async {
    _entries.removeWhere((entry) => entry.runId == runId);
  }

  @override
  Future<List<AgentHistoryEntry>> listHistory() async =>
      List<AgentHistoryEntry>.of(_entries);

  @override
  Future<AgentHistoryDetail?> loadHistoryDetail(String runId) async => null;

  @override
  Future<int> markInterruptedRuns() async => 0;

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
  }) async {}
}

class _FakeHistoryRepository implements AgentHistoryRepository {
  _FakeHistoryRepository({
    this.detail,
    this.entries = const <AgentHistoryEntry>[],
  });

  final AgentHistoryDetail? detail;
  final List<AgentHistoryEntry> entries;

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> deleteHistoryRun(String runId) async {}

  @override
  Future<List<AgentHistoryEntry>> listHistory() async => entries;

  @override
  Future<AgentHistoryDetail?> loadHistoryDetail(String runId) async => detail;

  @override
  Future<int> markInterruptedRuns() async => 0;

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
  }) async {}
}

Widget _app(Widget child, AgentHistoryRepository repository) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_preferences),
      agentHistoryRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

late SharedPreferences _preferences;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _preferences = await SharedPreferences.getInstance();
  });

  testWidgets('history list shows metadata without images', (tester) async {
    final entry = _entry();
    await tester.pumpWidget(
      _app(
        const AgentHistoryPage(),
        _FakeHistoryRepository(entries: <AgentHistoryEntry>[entry]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('何卒宜しくお願い致します。'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.textContaining('图片 1 张'), findsOneWidget);
    expect(find.textContaining('/private/'), findsNothing);
  });

  testWidgets('deleting a history row removes it from the list', (
    tester,
  ) async {
    final entry = _entry();
    await tester.pumpWidget(
      _app(
        const AgentHistoryPage(),
        _MutableHistoryRepository(<AgentHistoryEntry>[entry]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('何卒宜しくお願い致します。'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('何卒宜しくお願い致します。'), findsNothing);
    expect(find.text('还没有分析记录'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('empty history has an empty state', (tester) async {
    await tester.pumpWidget(
      _app(const AgentHistoryPage(), _FakeHistoryRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有分析记录'), findsOneWidget);
  });

  testWidgets('Agent history icon opens the history page', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.app_onboarding_completed': true,
    });
    _preferences = await SharedPreferences.getInstance();
    final entry = _entry();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
          agentHistoryRepositoryProvider.overrideWithValue(
            _FakeHistoryRepository(entries: <AgentHistoryEntry>[entry]),
          ),
        ],
        child: RikaiApp(key: UniqueKey()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('词典助手'));
    await tester.tap(find.text('词典助手'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('分析历史'), findsOneWidget);
    expect(find.text('何卒宜しくお願い致します。'), findsOneWidget);
  });

  testWidgets('history detail is read-only and shows OCR variants', (
    tester,
  ) async {
    final entry = _entry();
    await tester.pumpWidget(
      _app(
        const AgentHistoryDetailPage(runId: 'run-1'),
        _FakeHistoryRepository(
          entries: <AgentHistoryEntry>[entry],
          detail: AgentHistoryDetail(
            entry: entry,
            userText: '何卒宜しくお願い致します。',
            result: _result(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史记录只读；原图未保存。'), findsOneWidget);
    expect(find.textContaining('请务必'), findsWidgets);
    expect(find.textContaining('正式请求'), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.textContaining('paddle_v5/auto'), findsOneWidget);
    expect(find.textContaining('manga_ocr/vertical'), findsOneWidget);
    expect(find.text('当时选中'), findsOneWidget);
    expect(find.textContaining('/private/'), findsNothing);
  });
}
