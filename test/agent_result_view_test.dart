import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_pitch.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_evidence_panel.dart';
import 'package:rikai_mobile/features/agent/agent_pitch_accent.dart';
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

  testWidgets('strips YOMI wrappers in segment interpretations', (
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

    expect(find.text('正式请求（せいしき）'), findsOneWidget);
    expect(find.textContaining('[YOMI]'), findsNothing);
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
}
