import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_pitch.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_evidence_panel.dart';
import 'package:rikai_mobile/features/agent/agent_message_widgets.dart';
import 'package:rikai_mobile/features/agent/agent_pitch_accent.dart';
import 'package:rikai_mobile/features/agent/agent_rich_text.dart';
import 'package:rikai_mobile/features/agent/agent_result_view.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/agent_ui_strings.dart';
import 'package:rikai_mobile/services/agent/agent_validator.dart';

const _citation = AgentCitation(
  id: 'source-1',
  kind: 'mdict',
  dictionaryId: 'dict_a',
  dictionaryTitle: 'A',
  dictionaryOrder: 0,
  entryKey: '何卒',
  headword: '何卒',
  snippet: 'なにとぞ。どうか。',
  toolCallId: 'call-1',
);

const _result = AgentRunResult(
  input: AgentInputEnvelope(
    sessionId: 's1',
    mode: AgentMode.strict,
    sources: <AgentSourceInput>[
      AgentSourceInput(id: 'src-1', kind: AgentSourceKind.userText, text: '何卒'),
    ],
  ),
  evidence: AgentEvidenceBundle(
    sources: <AgentSourceEvidence>[
      AgentSourceEvidence(
        id: 'src-1',
        kind: 'user_text',
        text: '何卒',
        tokens: <AgentTokenEvidence>[
          AgentTokenEvidence(
            id: 't1',
            surface: '何卒',
            reading: 'なにとぞ',
            start: 0,
            end: 2,
            citationIds: <String>['source-1'],
          ),
        ],
      ),
    ],
    citations: <AgentCitation>[_citation],
  ),
  quotes: <AgentQuoteRef>[
    AgentQuoteRef(
      id: 'q1',
      sourceId: 'src-1',
      start: 0,
      end: 2,
      text: '何卒',
      origin: AgentQuoteOrigin.userText,
    ),
  ],
  analysis: AgentAnalysis(
    sourceId: 'src-1',
    translation: <AgentTranslation>[
      AgentTranslation(quoteId: 'q1', text: '请多关照。'),
    ],
    segments: <AgentSegment>[
      AgentSegment(
        id: 'seg-1',
        quoteId: 'q1',
        literal: '何卒',
        interpretation: '正式请求',
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
    unresolved: <AgentUnresolved>[
      AgentUnresolved(quoteId: 'q1', reason: '词典中未找到依据（q1）'),
    ],
  ),
  validation: AgentValidationResult(
    valid: true,
    errors: <String>[],
    citationsUsed: <String>['source-1'],
  ),
  sources: <AgentSourceVersion>[],
  dictionaryProfiles: <String>[],
);

const _unusedCitation = AgentCitation(
  id: 'source-2',
  kind: 'mdict',
  dictionaryId: 'dict_a',
  dictionaryTitle: 'A',
  dictionaryOrder: 0,
  entryKey: '未採用語',
  headword: '未採用語',
  snippet: 'retrieved but not adopted',
  toolCallId: 'call-2',
);

AgentRunResult _longResult() {
  return AgentRunResult(
    input: _result.input,
    evidence: _result.evidence,
    quotes: _result.quotes,
    analysis: AgentAnalysis(
      sourceId: 'src-1',
      translation: _result.analysis.translation,
      segments: <AgentSegment>[
        for (var index = 0; index < 12; index++)
          AgentSegment(
            id: 'seg-$index',
            quoteId: 'q1',
            literal: '何卒',
            interpretation: '逐句理解 $index',
            epistemic: AgentEpistemic.dictionaryFact,
            wordNotes: const <AgentWordNote>[
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
    ),
    validation: _result.validation,
    sources: _result.sources,
    dictionaryProfiles: _result.dictionaryProfiles,
  );
}

AgentRunResult _resultWithUnusedCitation() => AgentRunResult(
  input: _result.input,
  evidence: AgentEvidenceBundle(
    sources: _result.evidence.sources,
    citations: const <AgentCitation>[_citation, _unusedCitation],
  ),
  quotes: _result.quotes,
  analysis: _result.analysis,
  validation: const AgentValidationResult(
    valid: true,
    errors: <String>[],
    citationsUsed: <String>['source-1'],
  ),
  sources: _result.sources,
  dictionaryProfiles: _result.dictionaryProfiles,
);

AgentRunResult _resultWithPitch() => AgentRunResult(
  input: _result.input,
  evidence: _result.evidence,
  quotes: _result.quotes,
  analysis: _result.analysis,
  validation: _result.validation,
  sources: _result.sources,
  dictionaryProfiles: _result.dictionaryProfiles,
  pitchAccents: const <String, AgentPitchAccent>{
    't1': AgentPitchAccent(accentType: 2, moraCount: 2, moraPattern: 'LH'),
  },
);

AgentRunResult _resultWithSegments(List<AgentSegment> segments) {
  return AgentRunResult(
    input: _result.input,
    evidence: _result.evidence,
    quotes: _result.quotes,
    analysis: AgentAnalysis(
      sourceId: 'src-1',
      translation: _result.analysis.translation,
      segments: segments,
    ),
    validation: _result.validation,
    sources: _result.sources,
    dictionaryProfiles: _result.dictionaryProfiles,
  );
}

AgentRunResult _noAnalysisResult() {
  return AgentRunResult(
    input: _result.input,
    evidence: _result.evidence,
    quotes: _result.quotes,
    analysis: const AgentAnalysis(
      sourceId: 'src-1',
      noAnalysisReason: 'OCR 文本无法辨认',
    ),
    validation: const AgentValidationResult(
      valid: true,
      errors: <String>[],
      citationsUsed: <String>[],
    ),
    sources: _result.sources,
    dictionaryProfiles: _result.dictionaryProfiles,
  );
}

void main() {
  testWidgets('renders quotes, evidence and clickable citations', (
    tester,
  ) async {
    AgentCitation? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: _result,
              onCitationTap: (citation) => tapped = citation,
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('原文'), findsOneWidget);
    expect(find.text('逐句理解'), findsOneWidget);
    expect(find.text('词典依据'), findsOneWidget);
    expect(find.text('正式请求'), findsOneWidget);
    // The translation is already shown in the assistant bubble; the expanded
    // detail must not repeat it as a second section.
    expect(find.text('请多关照。'), findsNothing);
    expect(find.text('依据1'), findsWidgets);
    expect(find.text('词典中未找到依据'), findsOneWidget);
    expect(find.textContaining('（q1）'), findsNothing);
    expect(find.textContaining('· 查看'), findsNothing);

    final chip = find
        .ancestor(of: find.text('依据1').first, matching: find.byType(Container))
        .first;
    expect(tester.getSize(chip).width, lessThan(100));

    await tester.tap(find.text('依据1').first);
    expect(tapped?.id, 'source-1');
  });

  testWidgets('renders a UniDic pitch line only in word notes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: _resultWithPitch(),
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentPitchAccentText), findsOneWidget);
    expect(find.textContaining('请务必'), findsOneWidget);
  });

  testWidgets('labels the pitch row with the pitch info badge', (tester) async {
    final result = _resultWithPitch().copyWithRichText(
      const AgentRichTextOutputs(
        segmentTexts: <String>['正式请求'],
        segmentNotes: <String>['何卒（なにとぞ）：请务必'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badge = find.text('音调信息');
    final pitchWord = find.byType(AgentPitchAccentText);
    expect(badge, findsOneWidget);
    expect(pitchWord, findsOneWidget);
    expect(
      tester.getTopLeft(badge).dx,
      lessThan(tester.getTopLeft(pitchWord).dx),
    );
  });

  testWidgets('converts YOMI to RUBY in segment interpretations', (
    tester,
  ) async {
    final result = AgentRunResult(
      input: _result.input,
      evidence: _result.evidence,
      quotes: _result.quotes,
      analysis: AgentAnalysis(
        sourceId: 'src-1',
        segments: <AgentSegment>[
          const AgentSegment(
            id: 'seg-1',
            quoteId: 'q1',
            interpretation: '正式请求[YOMI]（せいしき）[/YOMI]',
            epistemic: AgentEpistemic.dictionaryFact,
          ),
        ],
      ),
      validation: _result.validation,
      sources: _result.sources,
      dictionaryProfiles: _result.dictionaryProfiles,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester.widget<AgentRichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AgentRichText &&
            widget.text.contains('[RUBY=せいしき]正式请求[/RUBY]'),
      ),
    );
    expect(rich.text, contains('[RUBY=せいしき]正式请求[/RUBY]'));
    expect(find.textContaining('[YOMI]'), findsNothing);
    expect(find.textContaining('（せいしき）'), findsNothing);
  });

  testWidgets('renders possible understandings as a green situation badge', (
    tester,
  ) async {
    final result = AgentRunResult(
      input: _result.input,
      evidence: _result.evidence,
      quotes: _result.quotes,
      analysis: AgentAnalysis(
        sourceId: 'src-1',
        segments: _result.analysis.segments,
        interpretations: const <AgentInterpretation>[
          AgentInterpretation(
            id: 'i1',
            label: 'A',
            meaning: '正式委托',
            confidence: 0.7,
            citationIds: <String>['source-1'],
          ),
        ],
      ),
      validation: _result.validation,
      sources: _result.sources,
      dictionaryProfiles: _result.dictionaryProfiles,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('正式委托'), findsOneWidget);
    expect(find.text('情况A'), findsOneWidget);
    expect(find.text('可能性70%'), findsOneWidget);
    expect(find.textContaining('A：'), findsNothing);
    expect(find.textContaining('（70%）'), findsNothing);
  });

  testWidgets(
    'shared interpretation citations render once below the last case',
    (tester) async {
      final result = AgentRunResult(
        input: _result.input,
        evidence: _result.evidence,
        quotes: _result.quotes,
        analysis: const AgentAnalysis(
          sourceId: 'src-1',
          interpretations: <AgentInterpretation>[
            AgentInterpretation(
              id: 'i1',
              label: 'A',
              meaning: '起点',
              confidence: 0.5,
              citationIds: <String>['source-1'],
            ),
            AgentInterpretation(
              id: 'i2',
              label: 'B',
              meaning: '原因',
              confidence: 0.5,
              citationIds: <String>['source-1'],
            ),
          ],
        ),
        validation: _result.validation,
        sources: _result.sources,
        dictionaryProfiles: _result.dictionaryProfiles,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentResultView(
                result: result,
                onCitationTap: (_) {},
                strings: AgentUiStrings.of(AgentUiLanguage.chinese),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('情况A'), findsOneWidget);
      expect(find.text('情况B'), findsOneWidget);
      expect(find.text('可能性50%'), findsNWidgets(2));
      // A and B share source-1, so the chip is rendered once for the section.
      expect(find.text('依据1'), findsOneWidget);
    },
  );

  testWidgets('different interpretation citations stay with their case', (
    tester,
  ) async {
    final result = AgentRunResult(
      input: _result.input,
      evidence: _result.evidence,
      quotes: _result.quotes,
      analysis: const AgentAnalysis(
        sourceId: 'src-1',
        interpretations: <AgentInterpretation>[
          AgentInterpretation(
            id: 'i1',
            label: 'A',
            meaning: '起点',
            confidence: 0.5,
            citationIds: <String>['source-1'],
          ),
          AgentInterpretation(
            id: 'i2',
            label: 'B',
            meaning: '原因',
            confidence: 0.5,
          ),
        ],
      ),
      validation: _result.validation,
      sources: _result.sources,
      dictionaryProfiles: _result.dictionaryProfiles,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('情况A'), findsOneWidget);
    expect(find.text('情况B'), findsOneWidget);
    expect(find.text('依据1'), findsOneWidget);
    // The A-only evidence stays inside A, above B, rather than becoming a
    // shared row below both cases.
    expect(
      tester.getTopLeft(find.text('依据1')).dy,
      lessThan(tester.getTopLeft(find.text('情况B')).dy),
    );
  });

  testWidgets('renders RUBY in the original and segment text', (tester) async {
    final result = AgentRunResult(
      input: _result.input,
      evidence: _result.evidence,
      quotes: _result.quotes,
      analysis: const AgentAnalysis(
        sourceId: 'src-1',
        segments: <AgentSegment>[
          AgentSegment(
            id: 'seg-1',
            quoteId: 'q1',
            interpretation: '正式请求',
            epistemic: AgentEpistemic.dictionaryFact,
          ),
        ],
      ),
      validation: _result.validation,
      sources: _result.sources,
      dictionaryProfiles: _result.dictionaryProfiles,
      richOriginalText: '[RUBY=なにとぞ]何卒[/RUBY]',
      richSegmentTexts: const <String>['[RUBY=せいしき]正式请求[/RUBY]'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('なにとぞ'), findsOneWidget);
    expect(find.text('せいしき'), findsOneWidget);
    expect(find.textContaining('[RUBY='), findsNothing);
  });

  testWidgets('rich-text update preserves scroll offset and visible blocks', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final base = _longResult();

    Widget build(AgentRunResult result) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: <Widget>[
            AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(build(base));
    await tester.pumpAndSettle();
    controller.jumpTo(600);
    await tester.pump();
    final before = controller.offset;
    expect(before, greaterThan(0));

    final updated = base.copyWithRichText(
      AgentRichTextOutputs(
        originalText: '[BOLD]何卒[/BOLD]',
        segmentTexts: List<String>.filled(12, ''),
        segmentNotes: List<String>.filled(12, ''),
      ),
    );
    await tester.pumpWidget(build(updated));
    await tester.pump();

    expect(controller.offset, closeTo(before, 0.5));
    // The progressive builder must not collapse back to the first 4 blocks.
    expect(find.textContaining('逐句理解 11'), findsOneWidget);
  });

  testWidgets('evidence header counts only adopted citations', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentEvidencePanel(
              result: _resultWithUnusedCitation(),
              onCitationTap: (_) {},
              onRetryProfile: (_) async {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );

    expect(find.text('详细解析 · 依据 1 条'), findsOneWidget);
    expect(find.text('未採用語'), findsNothing);

    await tester.tap(find.text('详细解析 · 依据 1 条'));
    await tester.pumpAndSettle();

    expect(find.text('A · 1 条'), findsOneWidget);
    expect(find.text('未採用語'), findsNothing);
    expect(find.text('依据1'), findsWidgets);
  });

  testWidgets('renders the same quote once per segment group', (tester) async {
    final result = _resultWithSegments(<AgentSegment>[
      const AgentSegment(
        id: 'seg-1',
        quoteId: 'q1',
        interpretation: '词典事实',
        epistemic: AgentEpistemic.dictionaryFact,
      ),
      const AgentSegment(
        id: 'seg-2',
        quoteId: 'q1',
        interpretation: '结构分析',
        epistemic: AgentEpistemic.structuralAnalysis,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<AgentRichText>(find.byType(AgentRichText))
        .map((widget) => widget.text)
        .toList();
    final quoteWidgets = texts.where((text) => text == '何卒').length;
    // One original-text box + one group header; the two segment cards must
    // not repeat the quote.
    expect(quoteWidgets, 2, reason: 'AgentRichText texts=$texts');
  });

  testWidgets('disabling result animation does not rebuild entrance fades', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: _result,
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
              animate: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('provisional to final keeps the same summary element', (
    tester,
  ) async {
    final strings = AgentUiStrings.of(AgentUiLanguage.chinese);
    Widget bubble({required bool provisional, required bool running}) {
      return MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentAssistantBubble(
            theme: AppTheme.light(),
            providerLabel: 'DeepSeek',
            mode: AgentMode.strict,
            running: running,
            provisional: provisional,
            cancelled: false,
            error: null,
            errorDetail: '',
            stageMessage: '正在生成',
            startedAt: DateTime(2026),
            thinkingStartedAt: DateTime(2026, 1, 1, 0, 0, 1),
            finishedAt: running ? null : DateTime(2026, 1, 1, 0, 0, 1),
            progressStep: running ? 2 : 4,
            evidenceCount: 0,
            citationCount: 0,
            uiLanguage: AgentUiLanguage.chinese,
            strings: strings,
            result: _result,
            onRetry: () {},
            onLooseRetry: null,
            onSettings: () {},
            onRegenerate: () {},
            onCopy: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(bubble(provisional: true, running: true));
    await tester.pump();
    final before = tester.element(
      find.byKey(const ValueKey<String>('agent-assistant-summary')),
    );

    await tester.pumpWidget(bubble(provisional: false, running: false));
    await tester.pump();
    final after = tester.element(
      find.byKey(const ValueKey<String>('agent-assistant-summary')),
    );

    expect(identical(before, after), isTrue);
  });

  testWidgets('renders a standalone NO_ANALYSIS reason', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentResultView(
              result: _noAnalysisResult(),
              onCitationTap: (_) {},
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法可靠分析'), findsOneWidget);
    expect(find.textContaining('OCR 文本无法辨认'), findsOneWidget);
  });
}
