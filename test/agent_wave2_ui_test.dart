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
import 'package:rikai_mobile/features/agent/agent_composer.dart';
import 'package:rikai_mobile/features/agent/agent_message_widgets.dart';
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

  test('awaiting profile still counts as an active run for elapsed time', () {
    final started = DateTime(2026, 1, 1);
    final snapshot = AgentRunSnapshot(
      status: AgentRunStatus.awaitingProfile,
      startedAt: started,
    );
    expect(snapshot.isRunning, isTrue);
    expect(snapshot.canCancel, isTrue);
  });

  testWidgets(
    'elapsed label includes wall-clock time spent away from the page',
    (tester) async {
      final started = DateTime(2026, 1, 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AgentElapsedLabel(
              startedAt: started,
              finishedAt: started.add(const Duration(seconds: 10)),
              language: AgentUiLanguage.chinese,
            ),
          ),
        ),
      );
      expect(find.text('已思考 10 秒'), findsOneWidget);
    },
  );
}
