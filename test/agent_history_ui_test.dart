import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/app.dart';
import 'package:lexicandy/core/models/agent/agent_analysis.dart';
import 'package:lexicandy/core/models/agent/agent_evidence.dart';
import 'package:lexicandy/core/models/agent/agent_history.dart';
import 'package:lexicandy/core/models/agent/agent_input.dart';
import 'package:lexicandy/core/models/agent/agent_quote.dart';
import 'package:lexicandy/core/theme/app_tokens.dart';
import 'package:lexicandy/features/agent/agent_history_detail_page.dart';
import 'package:lexicandy/features/agent/agent_history_page.dart';
import 'package:lexicandy/services/agent/agent_run.dart';
import 'package:lexicandy/services/agent/agent_validator.dart';
import 'package:lexicandy/services/storage/agent_history_store.dart';
import 'package:lexicandy/state/agent_history_recorder.dart';
import 'package:lexicandy/state/agent_providers.dart';
import 'package:lexicandy/state/providers.dart';
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

AgentHistoryEntry _entry({
  String runId = 'run-1',
  String title = '何卒宜しくお願い致します。',
  AgentHistoryStatus status = AgentHistoryStatus.done,
  String errorCode = '',
  int imageCount = 1,
  bool hasResult = true,
}) => AgentHistoryEntry(
  runId: runId,
  sessionId: 'session-1',
  title: title,
  status: status,
  mode: AgentMode.strict,
  startedAt: DateTime.now().subtract(const Duration(seconds: 2)),
  finishedAt: DateTime.now(),
  providerLabel: 'DeepSeek',
  imageCount: imageCount,
  hasResult: hasResult,
  errorCode: errorCode,
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
  Future<void> deleteHistoryRuns(Iterable<String> runIds) async {
    final ids = runIds.toSet();
    _entries.removeWhere((entry) => ids.contains(entry.runId));
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
  Future<void> deleteHistoryRuns(Iterable<String> runIds) async {}

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

  testWidgets('multi-select deletes the selected history rows', (tester) async {
    await tester.pumpWidget(
      _app(
        const AgentHistoryPage(),
        _MutableHistoryRepository(<AgentHistoryEntry>[
          _entry(runId: 'run-1', title: '一条记录'),
          _entry(runId: 'run-2', title: '二条记录'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.checklist), findsOneWidget);

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.byIcon(Icons.select_all), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('删除选中的记录？'), findsOneWidget);
    expect(find.textContaining('2 条'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('一条记录'), findsNothing);
    expect(find.text('二条记录'), findsNothing);
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
        child: LexiCandyApp(key: UniqueKey()),
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

  testWidgets('returning from detail keeps the history scroll position', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.app_onboarding_completed': true,
    });
    _preferences = await SharedPreferences.getInstance();
    final entries = <AgentHistoryEntry>[
      for (var index = 0; index < 12; index++)
        _entry(runId: 'run-$index', title: '记录 $index'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
          agentHistoryRepositoryProvider.overrideWithValue(
            _FakeHistoryRepository(
              entries: entries,
              detail: AgentHistoryDetail(entry: entries[6], userText: '何卒'),
            ),
          ),
        ],
        child: LexiCandyApp(key: UniqueKey()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('词典助手'));
    await tester.tap(find.text('词典助手'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('记录 0'), findsNothing);
    expect(find.text('记录 6'), findsOneWidget);

    await tester.tap(find.text('记录 6'));
    await tester.pumpAndSettle();
    expect(find.text('历史记录只读；原图未保存。'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('记录 0'), findsNothing);
    expect(find.text('记录 6'), findsOneWidget);
  });

  testWidgets('failed history shows a localized message, not a wire code', (
    tester,
  ) async {
    final entry = _entry(
      runId: 'run-failed',
      status: AgentHistoryStatus.error,
      errorCode: 'invalid_arguments',
      imageCount: 0,
      hasResult: false,
    );
    await tester.pumpWidget(
      _app(
        const AgentHistoryDetailPage(runId: 'run-failed'),
        _FakeHistoryRepository(
          entries: <AgentHistoryEntry>[entry],
          detail: AgentHistoryDetail(entry: entry, userText: '何卒'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('请求参数无效，请检查模型设置后重试'), findsOneWidget);
    expect(find.textContaining('INVALID_ARGUMENTS'), findsNothing);
    expect(find.textContaining('invalid_arguments'), findsNothing);
  });

  testWidgets('history detail copies the result as Markdown', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

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
    await tester.tap(find.byTooltip('复制结果为 Markdown'));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied, contains('何卒'));
    await tester.pump(const Duration(seconds: 3));
  });
}
