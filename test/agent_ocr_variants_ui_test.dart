import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_ocr.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_ocr_variants_panel.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/agent_ui_strings.dart';
import 'package:rikai_mobile/services/agent/agent_validator.dart';
import 'package:rikai_mobile/services/agent/ocr_consensus.dart';
import 'package:rikai_mobile/state/agent_ocr_variants.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const _baseline = AgentOcrVariant(
  id: 'var-1',
  engine: 'paddle_v5',
  mode: OcrMode.auto,
  text: '何卒コンニチハ',
  confidence: 0.9,
);

const _horizontal = AgentOcrVariant(
  id: 'var-2',
  engine: 'paddle_v5',
  mode: OcrMode.horizontal,
  text: '何卒コンバンハ',
  confidence: 0.8,
);

AgentRunResult _result() {
  final quality = OcrConsensus.assess(
    variant: _baseline,
    dictionaryHitRate: 0.2,
    contentWords: 5,
  );
  return AgentRunResult(
    input: const AgentInputEnvelope(
      sessionId: 's1',
      mode: AgentMode.strict,
      sources: <AgentSourceInput>[
        AgentSourceInput(
          id: 'src-1',
          kind: AgentSourceKind.imageOcr,
          imageId: 'img-1',
          selectedVariantId: 'var-1',
          variants: <AgentOcrVariant>[_baseline],
        ),
      ],
    ),
    evidence: const AgentEvidenceBundle(sources: <AgentSourceEvidence>[]),
    quotes: const <AgentQuoteRef>[],
    analysis: const AgentAnalysis(sourceId: 'src-1'),
    validation: const AgentValidationResult(
      valid: true,
      errors: <String>[],
      citationsUsed: <String>[],
    ),
    sources: const <AgentSourceVersion>[],
    dictionaryProfiles: const <String>[],
    ocrQuality: <String, OcrQuality>{'img-1': quality},
  );
}

AgentOcrVariantsState _state({String repairBaselineId = 'var-1'}) {
  return AgentOcrVariantsState(
    extraVariants: const <String, List<AgentOcrVariant>>{
      'img-1': <AgentOcrVariant>[_horizontal],
    },
    qualities: <String, Map<String, OcrQuality>>{
      'img-1': <String, OcrQuality>{
        'var-2': OcrConsensus.assess(variant: _horizontal),
      },
    },
    repairs: const <String, List<OcrRepairSuggestion>>{
      'img-1': <OcrRepairSuggestion>[
        OcrRepairSuggestion(
          original: 'ニチ',
          start: 4,
          end: 6,
          candidates: <OcrRepairCandidate>[OcrRepairCandidate(text: 'バン')],
        ),
      ],
    },
    repairBaselineIds: <String, String>{'img-1': repairBaselineId},
    generatedImages: const <String>{'img-1'},
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required void Function(String imageId, AgentOcrVariant variant) onReanalyze,
  AgentOcrVariantsState? variantsState,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AgentOcrVariantsPanel(
            result: _result(),
            variantsState: variantsState ?? _state(),
            strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            onReanalyze: onReanalyze,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows quality, chips, diff preview and variant action', (
    tester,
  ) async {
    AgentOcrVariant? selected;
    await _pumpPanel(
      tester,
      onReanalyze: (imageId, variant) {
        expect(imageId, 'img-1');
        selected = variant;
      },
    );

    expect(find.text('OCR 版本'), findsOneWidget);
    expect(find.text('识别质量偏低，建议对比其他 OCR 版本'), findsOneWidget);
    expect(find.text('paddle_v5 · 自动 · 90%'), findsOneWidget);

    await tester.tap(find.text('paddle_v5 · 横向 · 80%'));
    await tester.pump();
    expect(find.text('高亮文字与其他版本不一致'), findsOneWidget);

    await tester.tap(find.text('使用此版本重新分析'));
    await tester.pump();
    expect(selected?.id, 'var-2');
  });

  testWidgets(
    'applies a dictionary repair as a new dictionary-repair variant',
    (tester) async {
      AgentOcrVariant? selected;
      await _pumpPanel(
        tester,
        onReanalyze: (imageId, variant) {
          expect(imageId, 'img-1');
          selected = variant;
        },
      );

      expect(find.text('词典候选'), findsOneWidget);
      await tester.tap(find.text('バン'));
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.text, '何卒コンバンハ');
      expect(selected!.engine, 'dictionary_repair');
      expect(selected!.origin, AgentQuoteOrigin.dictionaryRepair);
    },
  );

  testWidgets('does not show repairs computed for a different baseline', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      onReanalyze: (imageId, variant) {},
      variantsState: _state(repairBaselineId: 'var-2'),
    );

    expect(find.text('词典候选'), findsNothing);
  });
}
