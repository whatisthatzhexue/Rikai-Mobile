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

const _mangaVertical = AgentOcrVariant(
  id: 'var-3',
  engine: 'manga_ocr',
  mode: OcrMode.vertical,
  text: '何卒コンバンハ',
  confidence: 0.7,
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

AgentRunResult _twoImageResult() {
  final base = _result();
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
        AgentSourceInput(
          id: 'src-2',
          kind: AgentSourceKind.imageOcr,
          imageId: 'img-2',
          selectedVariantId: 'var-1',
          variants: <AgentOcrVariant>[_baseline],
        ),
      ],
    ),
    evidence: base.evidence,
    quotes: base.quotes,
    analysis: base.analysis,
    validation: base.validation,
    sources: base.sources,
    dictionaryProfiles: base.dictionaryProfiles,
    ocrQuality: base.ocrQuality,
  );
}

AgentOcrVariantsState _state({String repairBaselineId = 'var-1'}) {
  return AgentOcrVariantsState(
    extraVariants: const <String, List<AgentOcrVariant>>{
      'img-1': <AgentOcrVariant>[_horizontal, _mangaVertical],
    },
    qualities: <String, Map<String, OcrQuality>>{
      'img-1': <String, OcrQuality>{
        'var-2': OcrConsensus.assess(variant: _horizontal),
        'var-3': OcrConsensus.assess(variant: _mangaVertical),
      },
    },
    repairs: const <String, List<OcrRepairSuggestion>>{
      'img-1': <OcrRepairSuggestion>[
        OcrRepairSuggestion(
          original: 'ニチ',
          start: 4,
          end: 6,
          candidates: <OcrRepairCandidate>[
            OcrRepairCandidate(text: 'バン'),
            OcrRepairCandidate(text: 'パン'),
          ],
        ),
        OcrRepairSuggestion(
          original: 'ハ',
          start: 6,
          end: 7,
          candidates: <OcrRepairCandidate>[OcrRepairCandidate(text: 'バ')],
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
  AgentRunResult? result,
  List<String> imagePaths = const <String>['/tmp/test-image.png'],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AgentOcrVariantsPanel(
            result: result ?? _result(),
            variantsState: variantsState ?? _state(),
            strings: AgentUiStrings.of(AgentUiLanguage.chinese),
            imagePaths: imagePaths,
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

    expect(find.text('文字识别结果'), findsOneWidget);
    expect(find.text('文字识别质量偏低，建议对比其他结果'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-ocr-image-1')), findsOneWidget);
    expect(find.text('置信度'), findsOneWidget);
    expect(find.text('词典命中'), findsOneWidget);
    expect(find.textContaining('假名'), findsNothing);
    expect(find.text('paddle_v5 · 自动 · 90%'), findsOneWidget);
    expect(find.text('paddle_v5 · 横向 · 80%'), findsOneWidget);
    expect(find.text('manga_ocr · 纵向 · 70%'), findsOneWidget);

    // Chips start at the left edge and wrap as a group instead of each one
    // occupying a centered full-width row.
    final autoTopLeft = tester.getTopLeft(find.text('paddle_v5 · 自动 · 90%'));
    final horizontalTopLeft = tester.getTopLeft(
      find.text('paddle_v5 · 横向 · 80%'),
    );
    expect(autoTopLeft.dy, horizontalTopLeft.dy);
    expect(autoTopLeft.dx, lessThan(horizontalTopLeft.dx));

    // The thumbnail decodes at display resolution; a full photo decode was
    // the mid-scroll hitch for long results.
    final thumbnail = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('agent-ocr-image-1')),
        matching: find.byType(Image),
      ),
    );
    expect(thumbnail.image, isA<ResizeImage>());
    final resized = thumbnail.image as ResizeImage;
    expect(resized.width, isNotNull);
    expect(resized.height, isNotNull);

    final horizontalChip = find
        .ancestor(
          of: find.text('paddle_v5 · 横向 · 80%'),
          matching: find.byType(InkWell),
        )
        .first;
    final chipSize = tester.getSize(horizontalChip);

    await tester.tap(find.text('paddle_v5 · 横向 · 80%'));
    await tester.pump();
    expect(find.text('高亮文字与其他版本不一致'), findsOneWidget);
    expect(tester.getSize(horizontalChip), chipSize);

    final diff = tester.widget<Text>(
      find.byKey(const ValueKey('agent-ocr-diff')),
    );
    final spans = (diff.textSpan! as TextSpan).children!.whereType<TextSpan>();
    final changed = spans.where((span) => span.style?.backgroundColor != null);
    expect(changed, isNotEmpty);
    expect(
      changed.first.style!.backgroundColor,
      AgentTokens.diffHighlightSurface,
    );
    expect(changed.first.style!.color, AgentTokens.diffHighlightText);

    await tester.tap(find.text('使用此版本重新分析'));
    await tester.pump();
    expect(selected?.id, 'var-2');
  });

  testWidgets(
    'selects one candidate per word and applies multiple selected words',
    (tester) async {
      AgentOcrVariant? selected;
      await _pumpPanel(
        tester,
        onReanalyze: (imageId, variant) {
          expect(imageId, 'img-1');
          selected = variant;
        },
      );

      Color? chipColor(String label) {
        final container = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        return (container.decoration as BoxDecoration?)?.color;
      }

      FilledButton actionButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '使用此版本重新分析'),
      );

      expect(find.text('词典候选'), findsOneWidget);
      expect(selected, isNull);
      expect(find.text('使用此版本重新分析'), findsOneWidget);
      // No selection: candidates stay grey and the bottom-right action button
      // is disabled.
      expect(chipColor('バン'), AppColors.surfaceMuted);
      expect(actionButton().onPressed, isNull);

      await tester.tap(find.text('バン'));
      await tester.pump();
      expect(selected, isNull);
      expect(chipColor('バン'), AgentTokens.citationSurface);
      expect(chipColor('パン'), AppColors.surfaceMuted);
      expect(actionButton().onPressed, isNotNull);

      // Selecting another candidate for the same word replaces the first one.
      await tester.tap(find.text('パン'));
      await tester.pump();
      expect(chipColor('バン'), AppColors.surfaceMuted);
      expect(chipColor('パン'), AgentTokens.citationSurface);

      // A different word can keep its own selection at the same time.
      await tester.tap(find.text('バ'));
      await tester.pump();
      expect(chipColor('パン'), AgentTokens.citationSurface);
      expect(chipColor('バ'), AgentTokens.citationSurface);

      await tester.tap(find.text('使用此版本重新分析'));
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.text, '何卒コンパンバ');
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

  testWidgets('comparison loading is scoped to one image', (tester) async {
    await _pumpPanel(
      tester,
      onReanalyze: (imageId, variant) {},
      result: _twoImageResult(),
      imagePaths: const <String>['/tmp/one.png', '/tmp/two.png'],
      variantsState: const AgentOcrVariantsState(
        loadingImageIds: <String>{'img-1'},
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在对比横向/纵向识别…'), findsOneWidget);
    expect(find.text('对比识别'), findsOneWidget);
  });
}
