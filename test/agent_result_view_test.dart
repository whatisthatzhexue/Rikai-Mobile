import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_result_view.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
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
            ),
          ),
        ),
      ),
    );

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
}
