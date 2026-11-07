import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/services/agent/agent_result_markdown.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/agent_ui_strings.dart';
import 'package:rikai_mobile/services/agent/agent_validator.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:rikai_mobile/features/agent/agent_composer.dart';
import 'package:rikai_mobile/features/agent/agent_message_widgets.dart';
import 'package:rikai_mobile/features/agent/agent_rich_text.dart';
import 'package:rikai_mobile/features/agent/agent_result_view.dart';
import 'package:rikai_mobile/features/capture/photo_viewer_page.dart';

const _citation = AgentCitation(
  id: 'source-1',
  kind: 'mdict',
  dictionaryId: 'dict-a',
  dictionaryTitle: 'A',
  dictionaryOrder: 0,
  entryKey: '何卒',
  headword: '何卒',
  snippet: 'なにとぞ。どうか。',
  toolCallId: 'call-1',
);

const _quote = AgentQuoteRef(
  id: 'q1',
  sourceId: 'src-1',
  start: 0,
  end: 2,
  text: '何卒',
  origin: AgentQuoteOrigin.userText,
);

const _analysis = AgentAnalysis(
  sourceId: 'src-1',
  translation: <AgentTranslation>[
    AgentTranslation(quoteId: 'q1', text: '请多关照。'),
  ],
  segments: <AgentSegment>[
    AgentSegment(
      id: 'seg-1',
      quoteId: 'q1',
      literal: '何卒',
      interpretation: '请务必。',
      epistemic: AgentEpistemic.dictionaryFact,
      wordNotes: <AgentWordNote>[
        AgentWordNote(
          tokenId: 't1',
          surface: '何卒',
          reading: 'なにとぞ',
          sense: '请务必',
          citationIds: <String>['source-1'],
        ),
      ],
    ),
  ],
  interpretations: <AgentInterpretation>[
    AgentInterpretation(
      id: 'i1',
      label: 'A',
      meaning: '正式请求',
      confidence: 0.8,
      citationIds: <String>['source-1'],
    ),
  ],
  unresolved: <AgentUnresolved>[
    AgentUnresolved(quoteId: 'q1', reason: '语境不明（q1）'),
  ],
);

const _result = AgentRunResult(
  input: AgentInputEnvelope(
    sessionId: 's1',
    mode: AgentMode.strict,
    sources: <AgentSourceInput>[],
  ),
  evidence: AgentEvidenceBundle(
    sources: <AgentSourceEvidence>[],
    citations: <AgentCitation>[_citation],
  ),
  quotes: <AgentQuoteRef>[_quote],
  analysis: _analysis,
  validation: AgentValidationResult(
    valid: true,
    errors: <String>[],
    citationsUsed: <String>['source-1'],
  ),
  sources: <AgentSourceVersion>[],
  dictionaryProfiles: <String>[],
  unavailableProfiles: <DictionaryProfileIssue>[
    DictionaryProfileIssue(
      dictionaryId: 'dict-b',
      title: 'B',
      reason: '档案请求失败',
    ),
  ],
);

AgentRunResult _resultWithAnalysis(AgentAnalysis analysis) => AgentRunResult(
  input: _result.input,
  evidence: _result.evidence,
  quotes: _result.quotes,
  analysis: analysis,
  validation: _result.validation,
  sources: _result.sources,
  dictionaryProfiles: _result.dictionaryProfiles,
  profileWarnings: _result.profileWarnings,
  unavailableProfiles: _result.unavailableProfiles,
  warnings: _result.warnings,
  coverageFallbackUsed: _result.coverageFallbackUsed,
  ocrQuality: _result.ocrQuality,
  pitchAccents: _result.pitchAccents,
  richOriginalText: _result.richOriginalText,
  richSegmentTexts: _result.richSegmentTexts,
  richSegmentNotes: _result.richSegmentNotes,
);

final _strings = AgentUiStrings.of(AgentUiLanguage.chinese);

void main() {
  testWidgets('composer shows multiple picked images and removes one', (
    tester,
  ) async {
    final removed = <String>[];
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => buildAgentComposer(
              context,
              controller: controller,
              focusNode: focus,
              imagePaths: const <String>['/tmp/a.jpg', '/tmp/b.jpg'],
              running: false,
              canSend: true,
              onPickImage: () {},
              onRemoveImage: removed.add,
              onSend: () {},
              onStop: () {},
              strings: _strings,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close).first);
    expect(removed, <String>['/tmp/a.jpg']);
  });

  testWidgets('sent images open the shared full-screen photo viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentUserBubble(
            text: '',
            hasImage: true,
            imagePaths: const <String>['/tmp/missing.jpg'],
            strings: _strings,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('agent-sent-image-0')));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewerPage), findsOneWidget);
  });

  testWidgets('result bubble has regenerate then copy actions', (tester) async {
    var regenerated = 0;
    var copied = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentAssistantBubble(
              theme: AppTheme.light(),
              providerLabel: 'DeepSeek',
              mode: AgentMode.strict,
              running: false,
              cancelled: false,
              error: null,
              errorDetail: '',
              stageMessage: '完成',
              startedAt: DateTime(2026, 1, 1),
              thinkingStartedAt: DateTime(2026, 1, 1, 0, 0, 1),
              finishedAt: DateTime(2026, 1, 1, 0, 0, 10),
              progressStep: 4,
              evidenceCount: 1,
              citationCount: 1,
              uiLanguage: AgentUiLanguage.chinese,
              strings: _strings,
              result: _result,
              onRetry: null,
              onLooseRetry: null,
              onSettings: () {},
              onRegenerate: () => regenerated++,
              onCopy: () => copied++,
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('重新生成结果'), findsOneWidget);
    expect(find.byTooltip('复制结果为 Markdown'), findsOneWidget);
    final icons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .map((button) => (button.icon as Icon).icon)
        .toList();
    expect(
      icons,
      containsAllInOrder(<IconData>[Icons.refresh, Icons.copy_outlined]),
    );

    await tester.tap(find.byTooltip('重新生成结果'));
    expect(regenerated, 1);
    await tester.tap(find.byTooltip('复制结果为 Markdown'));
    expect(copied, 1);
  });

  testWidgets('provisional result is visible before post-checks finish', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentAssistantBubble(
              theme: AppTheme.light(),
              providerLabel: 'DeepSeek',
              mode: AgentMode.strict,
              running: true,
              provisional: true,
              cancelled: false,
              error: null,
              errorDetail: '',
              stageMessage: '正在复核…',
              startedAt: DateTime(2026, 1, 1),
              thinkingStartedAt: DateTime(2026, 1, 1, 0, 0, 1),
              finishedAt: null,
              progressStep: 3,
              evidenceCount: 1,
              citationCount: 1,
              uiLanguage: AgentUiLanguage.chinese,
              strings: _strings,
              result: _result,
              onRetry: null,
              onLooseRetry: null,
              onSettings: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('结果已出，正在复核…'), findsOneWidget);
    expect(find.text('请多关照。'), findsOneWidget);
    expect(find.text('正在重新生成，下面显示上次结果'), findsNothing);
    expect(find.byTooltip('重新生成结果'), findsNothing);
    expect(find.byTooltip('复制结果为 Markdown'), findsNothing);
  });

  testWidgets(
    'completed assistant bubble renders the summary without raw tags',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentAssistantBubble(
                theme: AppTheme.light(),
                providerLabel: 'DeepSeek',
                mode: AgentMode.strict,
                running: false,
                provisional: false,
                cancelled: false,
                error: null,
                errorDetail: '',
                stageMessage: '',
                startedAt: DateTime(2026, 1, 1),
                thinkingStartedAt: DateTime(2026, 1, 1, 0, 0, 1),
                finishedAt: DateTime(2026, 1, 1, 0, 0, 1),
                progressStep: 4,
                evidenceCount: 1,
                citationCount: 1,
                uiLanguage: AgentUiLanguage.chinese,
                strings: _strings,
                result: _result,
                onRetry: null,
                onLooseRetry: null,
                onSettings: () {},
                onRegenerate: () {},
                onCopy: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('请多关照。'), findsOneWidget);
      expect(find.textContaining('[RUBY='), findsNothing);
    },
  );

  testWidgets('assistant bubble renders local RUBY in its summary', (
    tester,
  ) async {
    final result = _resultWithAnalysis(
      const AgentAnalysis(
        sourceId: 'src-1',
        translation: <AgentTranslation>[
          AgentTranslation(quoteId: 'q1', text: '何卒[YOMI]なにとぞ[/YOMI]'),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentAssistantBubble(
              theme: AppTheme.light(),
              providerLabel: 'DeepSeek',
              mode: AgentMode.strict,
              running: false,
              cancelled: false,
              error: null,
              errorDetail: '',
              stageMessage: '',
              startedAt: DateTime(2026, 1, 1),
              thinkingStartedAt: DateTime(2026, 1, 1, 0, 0, 1),
              finishedAt: DateTime(2026, 1, 1, 0, 0, 1),
              progressStep: 4,
              evidenceCount: 1,
              citationCount: 1,
              uiLanguage: AgentUiLanguage.chinese,
              strings: _strings,
              result: result,
              onRetry: null,
              onLooseRetry: null,
              onSettings: () {},
              onRegenerate: () {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentRichText), findsWidgets);
    expect(find.textContaining('何卒'), findsWidgets);
    expect(find.textContaining('[YOMI]'), findsNothing);
    expect(find.textContaining('[RUBY='), findsNothing);
  });

  test('copyable Markdown contains structured sections and no raw JSON', () {
    final markdown = buildAgentResultMarkdown(_result, _strings);
    expect(markdown, contains('## 原文'));
    expect(markdown, contains('## 译文'));
    expect(markdown, contains('## 逐句理解'));
    expect(markdown, contains('## 词典依据'));
    expect(markdown, contains('依据1'));
    expect(markdown, contains('何卒'));
    expect(markdown, isNot(contains('（q1）')));
    expect(markdown, isNot(contains('reasoning')));
    expect(markdown, isNot(contains('/tmp/')));
  });

  test('copyable Markdown strips display tags but keeps readings', () {
    const yomiAnalysis = AgentAnalysis(
      sourceId: 'src-1',
      translation: <AgentTranslation>[
        AgentTranslation(
          quoteId: 'q1',
          text:
              '请多关照[YOMI]（ます）[/YOMI]'
              '[RUBY=shabai]シャバイ[/RUBY]。',
        ),
      ],
      segments: <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          interpretation:
              '请务必[YOMI]（ます）[/YOMI]'
              '[RUBY=せいしき]正式请求[/RUBY]。',
          epistemic: AgentEpistemic.dictionaryFact,
        ),
      ],
    );
    final result = AgentRunResult(
      input: _result.input,
      evidence: _result.evidence,
      quotes: _result.quotes,
      analysis: yomiAnalysis,
      validation: _result.validation,
      sources: _result.sources,
      dictionaryProfiles: _result.dictionaryProfiles,
    );
    final markdown = buildAgentResultMarkdown(result, _strings);

    expect(markdown, contains('ます【请多关照】shabai【シャバイ】。'));
    expect(markdown, contains('ます【请务必】せいしき【正式请求】。'));
    expect(markdown, isNot(contains('[YOMI]')));
    expect(markdown, isNot(contains('[RUBY')));
  });

  test('markdown groups repeated quotes and warns about truncation', () {
    final analysis = AgentAnalysis(
      sourceId: 'src-1',
      translation: const <AgentTranslation>[
        AgentTranslation(quoteId: 'q1', text: '请多关照。'),
      ],
      segments: const <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          interpretation: '词典事实',
          epistemic: AgentEpistemic.dictionaryFact,
          wordNotes: <AgentWordNote>[
            AgentWordNote(
              tokenId: 't1',
              surface: '何卒',
              reading: 'なにとぞ',
              sense: '请务必',
              citationIds: <String>['source-1'],
            ),
          ],
        ),
        AgentSegment(
          id: 'seg-2',
          quoteId: 'q1',
          interpretation: '结构分析',
          epistemic: AgentEpistemic.structuralAnalysis,
        ),
      ],
      truncated: true,
    );
    final result = AgentRunResult(
      input: _result.input,
      evidence: _result.evidence,
      quotes: _result.quotes,
      analysis: analysis,
      validation: _result.validation,
      sources: _result.sources,
      dictionaryProfiles: _result.dictionaryProfiles,
    );
    final markdown = buildAgentResultMarkdown(result, _strings);
    final quoteLines = RegExp(
      r'^> 何卒$',
      multiLine: true,
    ).allMatches(markdown).length;
    // Original section + one segment group. The two segments must not repeat
    // the same quote.
    expect(quoteLines, 2);
    expect(markdown, contains('なにとぞ【何卒】：请务必'));
    expect(markdown, contains('已按上限缩减输出'));
  });

  testWidgets('retry dictionary shows a spinner while the request is running', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: _result,
              strings: _strings,
              onCitationTap: (_) {},
              onRetryProfile: (_) => pending.future,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('重试此词典'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('重试此词典'), findsOneWidget);
  });

  test('awaiting profile still counts as an active run for elapsed time', () {
    final started = DateTime(2026, 1, 1);
    final snapshot = AgentRunSnapshot(
      status: AgentRunStatus.awaitingProfile,
      startedAt: started,
    );
    expect(snapshot.isRunning, isTrue);
    expect(snapshot.canCancel, isTrue);
  });

  testWidgets('finished elapsed label reports total task duration honestly', (
    tester,
  ) async {
    final started = DateTime(2026, 1, 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentElapsedLabel(
            startedAt: started,
            thinkingStartedAt: started.add(const Duration(seconds: 2)),
            finishedAt: started.add(const Duration(seconds: 10)),
            language: AgentUiLanguage.chinese,
          ),
        ),
      ),
    );
    expect(find.text('任务用时 10 秒'), findsOneWidget);
    expect(find.textContaining('已思考'), findsNothing);
  });

  testWidgets('elapsed label shows task time before model generation', (
    tester,
  ) async {
    final started = DateTime.now().subtract(const Duration(seconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentElapsedLabel(
            startedAt: started,
            language: AgentUiLanguage.chinese,
          ),
        ),
      ),
    );
    expect(find.textContaining('任务已进行'), findsOneWidget);
    expect(find.textContaining('已思考'), findsNothing);
  });

  testWidgets('elapsed label switches to thinking time at reasoning stage', (
    tester,
  ) async {
    final started = DateTime.now().subtract(const Duration(seconds: 10));
    final thinking = DateTime.now().subtract(const Duration(seconds: 4));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentElapsedLabel(
            startedAt: started,
            thinkingStartedAt: thinking,
            language: AgentUiLanguage.chinese,
          ),
        ),
      ),
    );
    expect(find.textContaining('已思考'), findsOneWidget);
    expect(find.textContaining('任务已进行'), findsNothing);
  });

  testWidgets('slow-request advisory is orange and non-blocking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentAssistantBubble(
            theme: AppTheme.light(),
            providerLabel: 'DeepSeek',
            mode: AgentMode.strict,
            running: true,
            cancelled: false,
            error: null,
            errorDetail: '',
            stageMessage: '生成结果',
            startedAt: DateTime.now().subtract(const Duration(seconds: 40)),
            thinkingStartedAt: DateTime.now().subtract(
              const Duration(seconds: 35),
            ),
            finishedAt: null,
            slowRequestWarning: true,
            progressStep: 2,
            evidenceCount: 1,
            citationCount: 1,
            uiLanguage: AgentUiLanguage.chinese,
            strings: _strings,
            result: null,
            onRetry: null,
            onLooseRetry: null,
            onSettings: () {},
          ),
        ),
      ),
    );

    final warning = tester.widget<Text>(find.text('本次处理时间较长，请耐心等待'));
    expect(warning.style?.color, AppColors.warning);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
